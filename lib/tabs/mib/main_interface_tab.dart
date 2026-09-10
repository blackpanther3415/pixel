import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import '../../models/provider.dart';
import '../../widgets/common.dart';

/// MI.B — Main Interface. The primary chat + controls surface of Pixel.
class MainInterfaceTab extends StatefulWidget {
  final AppState state;
  const MainInterfaceTab({super.key, required this.state});

  @override
  State<MainInterfaceTab> createState() => _MainInterfaceTabState();
}

class _MainInterfaceTabState extends State<MainInterfaceTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  List<Map<String, Object?>> _chats = [];
  List<ProviderConfig> _providers = [];
  String _selectedProvider = '';
  String _selectedModel = '';
  bool _streaming = false;
  String? _streamedFull;
  int? _activeChatId;
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final s = widget.state.services;
    _providers = await s.db.listProviders();
    final settings = await s.db.getSettings();
    await s.chat.loadFromSettings(settings);
    _selectedProvider = settings.defaultProviderId;
    _selectedModel = settings.defaultModel;
    await _reloadChats();
    if (_chats.isNotEmpty) {
      final id = _chats.first['id'] as int;
      await _openChat(id);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadChats() async {
    _chats = await widget.state.services.db.listChats();
  }

  Future<void> _newChat() async {
    final s = widget.state.services;
    final id = await s.chat.newChat(
        'New conversation ${DateTime.now().hour}:${DateTime.now().minute}');
    await _openChat(id);
    await _reloadChats();
    if (mounted) setState(() {});
  }

  Future<void> _openChat(int id) async {
    final s = widget.state.services;
    await s.chat.setActiveChat(id);
    _activeChatId = id;
    _messages = await s.chat.history();
    if (mounted) setState(() {});
    _scrollBottom();
  }

  Future<void> _deleteChat(int id) async {
    await widget.state.services.chat.deleteChat(id);
    _activeChatId = null;
    _messages = [];
    await _reloadChats();
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _streaming) return;
    _input.clear();
    setState(() {
      _streaming = true;
      _streamedFull = '';
    });

    final s = widget.state.services;
    if (_activeChatId == null) {
      await _newChat();
    }
    s.chat.setManualOverride(_selectedProvider, _selectedModel);

    final stream = await s.chat.sendMessage(
      text,
      onDelta: (mid, full) {
        if (mounted) {
          setState(() => _streamedFull = full);
          _scrollBottom();
        }
      },
    );
    _sub?.cancel();
    _sub = stream.listen(
      (_) {},
      onDone: () async {
        _messages = await s.chat.history();
        if (mounted) {
          setState(() {
            _streaming = false;
            _streamedFull = null;
          });
          _scrollBottom();
        }
        await _reloadChats();
        if (mounted) setState(() {});
      },
      onError: (e) async {
        _messages = await s.chat.history();
        if (mounted) {
          setState(() {
            _streaming = false;
            _streamedFull = null;
          });
        }
      },
    );
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final wide = MediaQuery.of(context).size.width > 860;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) _ChatList(
              chats: _chats,
              activeId: _activeChatId,
              onNew: _newChat,
              onOpen: _openChat,
              onDelete: _deleteChat,
            ),
        Expanded(child: _buildChat(wide)),
      ],
    );
  }

  Widget _buildChat(bool wide) {
    return Column(
      children: [
        _ControlsBar(
          providers: _providers,
          provider: _selectedProvider,
          model: _selectedModel,
          onProvider: (v) => setState(() {
            _selectedProvider = v;
            _selectedModel = '';
          }),
          onModel: (v) => setState(() => _selectedModel = v),
          onClear: () async {
            await _newChat();
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: _messages.isEmpty && _streamedFull == null
              ? const EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Talk to Pixel',
                  message:
                      'Send a message through the G.B security gateway. '
                      'Pixel routes it to the cheapest or fastest model '
                      'configured.',
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _messages.length +
                      (_streaming ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _messages.length) {
                      return _StreamingBubble(_streamedFull ?? '');
                    }
                    return _MessageBubble(_messages[i]);
                  },
                ),
        ),
        _Composer(
          controller: _input,
          busy: _streaming,
          onSend: _send,
          state: widget.state,
        ),
      ],
    );
  }
}

class _ChatList extends StatelessWidget {
  final List<Map<String, Object?>> chats;
  final int? activeId;
  final Future<void> Function() onNew;
  final Future<void> Function(int) onOpen;
  final Future<void> Function(int) onDelete;
  const _ChatList({
    required this.chats,
    required this.activeId,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Conversations',
                      style: TextStyle(
                          color: AppColors.textHigh,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  color: AppColors.primaryLight,
                  onPressed: onNew,
                  tooltip: 'New conversation',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (context, i) {
                final c = chats[i];
                final id = c['id'] as int;
                final title = (c['title'] as String?) ?? 'Chat';
                final count = (c['count'] as int?) ?? 0;
                final selected = id == activeId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.15),
                  title: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text('$count messages',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => onOpen(id),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        size: 16, color: AppColors.textLow),
                    onSelected: (v) {
                      if (v == 'delete') onDelete(id);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsBar extends StatelessWidget {
  final List<ProviderConfig> providers;
  final String provider;
  final String model;
  final ValueChanged<String> onProvider;
  final ValueChanged<String> onModel;
  final VoidCallback onClear;
  const _ControlsBar({
    required this.providers,
    required this.provider,
    required this.model,
    required this.onProvider,
    required this.onModel,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = providers.where((p) => p.enabled).toList();
    final current = enabled.where((p) => p.id == provider).firstOrNull ??
        enabled.firstOrNull;
    final models = current?.models ?? const <ProviderModel>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.router, size: 18, color: AppColors.accent),
          const Text('Route',
              style: TextStyle(color: AppColors.textMid, fontSize: 11)),
          DropdownButton<String>(
            value: current?.id,
            dropdownColor: AppColors.surfaceLight,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: AppColors.textHigh, fontSize: 13),
            items: [
              for (final p in enabled)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => v != null ? onProvider(v) : null,
          ),
          if (models.isNotEmpty) ...[
            DropdownButton<String>(
              value: model.isEmpty ? null : model,
              hint: const Text('smart',
                  style: TextStyle(color: AppColors.textLow, fontSize: 13)),
              dropdownColor: AppColors.surfaceLight,
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: AppColors.textHigh, fontSize: 13),
              items: [
                for (final m in models)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => v != null ? onModel(v) : null,
            ),
            const Tooltip(
              message: 'Manual override is ON. Leave model empty for smart routing.',
              child: Icon(Icons.info_outline,
                  size: 14, color: AppColors.textLow),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.add_comment, size: 16),
            label: const Text('New chat'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage m;
  const _MessageBubble(this.m);

  @override
  Widget build(BuildContext context) {
    final isUser = m.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.68 : 0.85)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isUser
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isUser ? 'YOU' : 'PIXEL',
                    style: TextStyle(
                        color: isUser ? AppColors.primaryLight : AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                const SizedBox(width: 8),
                if (!isUser && m.providerId != null)
                  Flexible(
                    child: Text('via ${m.providerId}/${m.model ?? ""}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textLow, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(m.content.isEmpty ? ' ' : m.content,
                style: TextStyle(
                  color: m.blocked ? AppColors.warn : AppColors.textHigh,
                  fontSize: 14,
                  height: 1.4,
                )),
            if (m.blocked)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('⛔ BLOCKED BY G.B',
                    style:
                        TextStyle(color: AppColors.bad, fontSize: 10)),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  final String text;
  const _StreamingBubble(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3, right: 8),
              child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            Expanded(
              child: Text(text.isEmpty ? 'Thinking…' : text,
                  style: const TextStyle(
                      color: AppColors.textHigh, fontSize: 14, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final Future<void> Function() onSend;
  final AppState state;
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _VoiceButton(onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Voice input is active on devices with a microphone. '
                        'Desktop TTS/STT needs the platform engine enabled in settings.')),
              );
            }),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => busy ? null : onSend(),
                decoration: const InputDecoration(
                  hintText: 'Message Pixel (all traffic gated by G.B)…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: busy ? null : onSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  final VoidCallback onTap;
  const _VoiceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: const Icon(Icons.mic, size: 20),
      tooltip: 'Voice input',
    );
  }
}