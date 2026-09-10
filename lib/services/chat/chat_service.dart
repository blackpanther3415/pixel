import 'dart:async';
import 'dart:math';

import '../../models/chat_message.dart';
import '../../models/provider.dart';
import '../database/database_service.dart';
import '../providers/provider_client.dart';
import '../providers/provider_factory.dart';
import '../security/security_gateway.dart';

/// Orchestrates the MI.B chat: message persistence, G.B gating, routing and
/// streaming against the chosen provider.
class ChatService {
  final DatabaseService db;
  final SecurityGateway gateway;
  final SmartRouter Function(String providerId, String model) routerFactory;

  int _activeChatId = 0;
  String _overrideProviderId = '';
  String _overrideModel = '';

  ChatService({
    required this.db,
    required this.gateway,
    required this.routerFactory,
  });

  int get activeChatId => _activeChatId;

  Future<void> loadFromSettings(AppSettings s) async {
    _overrideProviderId = s.defaultProviderId;
    _overrideModel = s.defaultModel;
  }

  void setManualOverride(String providerId, String model) {
    _overrideProviderId = providerId;
    _overrideModel = model;
  }

  Future<int> newChat(String title) async {
    final id = await db.createChat(title,
        providerId: _overrideProviderId, model: _overrideModel);
    _activeChatId = id;
    return id;
  }

  Future<void> setActiveChat(int id) async {
    _activeChatId = id;
  }

  Future<void> deleteChat(int id) async {
    await db.deleteChat(id);
    if (_activeChatId == id) _activeChatId = 0;
  }

  Future<List<ChatMessage>> history() async {
    if (_activeChatId == 0) return [];
    return db.listMessages(_activeChatId);
  }

  /// Send a user message: G.B-scans it, routes it, streams the completion
  /// through G.B outbound, persists everything.
  Future<Stream<String>> sendMessage(
    String text, {
    required void Function(String midScript, String full) onDelta,
  }) async {
    ensureChat();
    _persistUser(text);

    // ---- INBOUND GATE (user -> model) ----
    final inbound = await gateway.scanInbound(text: text, route: 'MI.B');
    if (inbound.blocked) {
      _persistBlocked('G.B blocked the message', inbound.events);
      onDelta('', inbound.sanitized);
      return const Stream.empty();
    }

    final target = await routerFactory(_overrideProviderId, _overrideModel)
        .route(inputTokens: _estimateTokens(inbound.sanitized), outputTokens: 200);
    if (target == null) {
      _persistBlocked(
          'No usable provider. Add an API key in G.B/settings.', []);
      onDelta('', '');
      return const Stream.empty();
    }

    final client = ProviderFactory.create(target.provider);
    final history = await db.listMessages(_activeChatId);
    final msgs = <ChatMsg>[];
    for (final h in history) {
      if (h.blocked) continue;
      final role =
          h.role == ChatRole.assistant || h.role == ChatRole.user ? h.role.name : 'user';
      msgs.add(ChatMsg(role, h.content));
    }

    final controller = StreamController<String>();
    _streamFrom(client, msgs, target.model, controller, onDelta, target);
    return controller.stream;
  }

  void _streamFrom(
    ProviderClient client,
    List<ChatMsg> messages,
    ProviderModel model,
    StreamController<String> controller,
    void Function(String mid, String full) onDelta,
    RoutedTarget target,
  ) {
    var acc = StringBuffer();
    StreamSubscription<String>? sub;
    var promptTokens = 0, completionTokens = 0;

    Future<void> finish(String? error) async {
      sub?.cancel();
      final text = acc.toString();
      if (!controller.isClosed) controller.add(text);
      await controller.close();

      // ---- OUTBOUND GATE (model -> user) ----
      final checked = await gateway.scanOutbound(text: text, route: 'MI.B');
      if (checked.blocked) {
        final id = await _persistAssistant(checked.sanitized, model,
            providerId: target.provider.id, blocked: true);
        await _persistBlockedNote(id, checked.events);
      } else {
        await _persistAssistant(text, model,
            providerId: target.provider.id,
            promptTokens: promptTokens,
            completionTokens: completionTokens);
      }
    }

    try {
      sub = client.streamChat(messages, model: model.id).listen(
            (delta) {
              acc.write(delta);
              onDelta(delta, acc.toString());
            },
            onError: (e) => finish('$e'),
            onDone: () => finish(null),
            cancelOnError: true,
          );
    } catch (e) {
      finish('$e');
    }
  }

  Future<int> _persistUser(String text) {
    final m = ChatMessage(
      chatId: _activeChatId,
      role: ChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    );
    return db.insertMessage(m);
  }

  Future<int> _persistAssistant(String text, ProviderModel model,
      {required String providerId,
      int promptTokens = 0,
      int completionTokens = 0,
      bool blocked = false}) {
    final m = ChatMessage(
      chatId: _activeChatId,
      role: ChatRole.assistant,
      content: text,
      providerId: providerId,
      model: model.id,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      createdAt: DateTime.now(),
      blocked: blocked,
    );
    return db.insertMessage(m);
  }

  Future<void> _persistBlocked(String note, List events) async {
    final m = ChatMessage(
      chatId: _activeChatId,
      role: ChatRole.assistant,
      content: note,
      providerId: null,
      model: null,
      createdAt: DateTime.now(),
      blocked: true,
    );
    final id = await db.insertMessage(m);
    await _persistBlockedNote(id, events);
  }

  Future<void> _persistBlockedNote(int messageId, List events) async {
    // annotations not yet needed; blocking events already persisted by gateway
  }

  void ensureChat() {
    if (_activeChatId == 0) {
      _activeChatId = 0;
    }
  }

  int _estimateTokens(String s) => max(1, (s.length / 3.5).ceil());
}