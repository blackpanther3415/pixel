import 'package:intl/intl.dart';

enum ChatRole { system, user, assistant, tool }

class ChatMessage {
  final int? id;
  final int chatId;
  final ChatRole role;
  final String content;
  final String? providerId;
  final String? model;
  final int? promptTokens;
  final int? completionTokens;
  final DateTime createdAt;
  final bool blocked;

  const ChatMessage({
    this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.providerId,
    this.model,
    this.promptTokens,
    this.completionTokens,
    required this.createdAt,
    this.blocked = false,
  });

  ChatMessage copyWith({
    int? id,
    int? chatId,
    ChatRole? role,
    String? content,
    String? providerId,
    String? model,
    int? promptTokens,
    int? completionTokens,
    DateTime? createdAt,
    bool? blocked,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        chatId: chatId ?? this.chatId,
        role: role ?? this.role,
        content: content ?? this.content,
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
        promptTokens: promptTokens ?? this.promptTokens,
        completionTokens: completionTokens ?? this.completionTokens,
        createdAt: createdAt ?? this.createdAt,
        blocked: blocked ?? this.blocked,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'chat_id': chatId,
        'role': role.name,
        'content': content,
        'provider_id': providerId,
        'model': model,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'created_at': createdAt.toIso8601String(),
        'blocked': blocked ? 1 : 0,
      };

  factory ChatMessage.fromDb(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as int?,
        chatId: m['chat_id'] as int,
        role: ChatRole.values.firstWhere(
            (r) => r.name == m['role'],
            orElse: () => ChatRole.user),
        content: (m['content'] as String?) ?? '',
        providerId: m['provider_id'] as String?,
        model: m['model'] as String?,
        promptTokens: m['prompt_tokens'] as int?,
        completionTokens: m['completion_tokens'] as int?,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.now(),
        blocked: (m['blocked'] as int? ?? 0) == 1,
      );

  String get timeLabel => DateFormat('HH:mm:ss').format(createdAt);
}