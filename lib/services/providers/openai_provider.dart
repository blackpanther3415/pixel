import 'dart:async';
import 'dart:convert';

import '../../models/provider.dart';
import 'provider_client.dart';

/// OpenAI / compatible chat completions + embeddings.
class OpenAIProvider extends HttpProviderBase implements ProviderClient {
  @override
  final ProviderConfig config;

  OpenAIProvider({required this.config})
      : super(
          baseUrl: config.baseUrl ?? 'https://api.openai.com/v1',
          apiKey: config.apiKey,
        );

  @override
  Stream<String> streamChat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) {
    final body = <String, Object?>{
      'model': model ?? _pickModel(),
      'messages': [
        for (final m in messages) {'role': m.role, 'content': m.content}
      ],
      'temperature': temperature,
      'stream': true,
    };
    return streamSse('/chat/completions', body);
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
        'model': model ?? _pickModel(),
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
    if (model == null && !(_hasEmbedder())) return null;
    final resp = await dio.post<Map<String, dynamic>>(
      '/embeddings',
      data: jsonEncode({
        'model': model ?? 'text-embedding-3-small',
        'input': text,
      }),
    );
    final data = (resp.data!['data'] as List?)?.first as Map<String, dynamic>?;
    final vec = data?['embedding'] as List?;
    if (vec == null) return null;
    return vec.map((e) => (e as num).toDouble()).toList();
  }

  bool _hasEmbedder() => config.models.any((m) => m.supportsEmbeddings);

  String _pickModel() {
    final candidate = config.models.where((m) => !m.supportsEmbeddings).toList();
    return (candidate.isNotEmpty ? candidate.last : config.models.last).id;
  }
}