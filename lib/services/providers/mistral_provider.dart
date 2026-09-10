import 'dart:async';
import 'dart:convert';

import '../../models/provider.dart';
import 'provider_client.dart';

/// Mistral chat completions (OpenAI-compatible).
class MistralProvider extends HttpProviderBase implements ProviderClient {
  @override
  final ProviderConfig config;

  MistralProvider({required this.config})
      : super(
          baseUrl: 'https://api.mistral.ai/v1',
          apiKey: config.apiKey,
        );

  @override
  Stream<String> streamChat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) {
    return streamSse('/chat/completions', {
      'model': model ?? config.models.last.id,
      'messages': [
        for (final m in messages) {'role': m.role, 'content': m.content}
      ],
      'temperature': temperature,
      'stream': true,
    });
  }

  @override
  Future<CompletionResult> chat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) async {
    final resp = await dio.post<Map<String, dynamic>>(
      '/chat/completions',
      data: jsonEncode({
        'model': model ?? config.models.last.id,
        'messages': [
          for (final m in messages) {'role': m.role, 'content': m.content}
        ],
        'temperature': temperature,
      }),
    );
    final data = resp.data!;
    final text = (data['choices'] as List?)?.first['message']?['content'] as String? ?? '';
    final usage = data['usage'] as Map<String, dynamic>?;
    return CompletionResult(
      text: text,
      promptTokens: (usage?['prompt_tokens'] as int?) ?? 0,
      completionTokens: (usage?['completion_tokens'] as int?) ?? 0,
      model: data['model'] as String?,
    );
  }

  @override
  Future<List<double>?> embed(String text, {String? model}) async {
    final resp = await dio.post<Map<String, dynamic>>(
      '/embeddings',
      data: jsonEncode({
        'model': model ?? 'mistral-embed',
        'input': text,
      }),
    );
    final vec = (resp.data!['data'] as List?)?.first['embedding'] as List?;
    return vec?.map((e) => (e as num).toDouble()).toList();
  }
}