import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/provider.dart';
import 'provider_client.dart';

/// Anthropic Messages API (streaming + non-streaming).
class AnthropicProvider implements ProviderClient {
  @override
  final ProviderConfig config;
  final Dio dio;

  AnthropicProvider({required this.config})
      : dio = Dio(BaseOptions(
          baseUrl: 'https://api.anthropic.com/v1',
          headers: {
            'x-api-key': config.apiKey ?? '',
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ));

  @override
  Future<CompletionResult> chat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) async {
    final resp = await dio.post<Map<String, dynamic>>(
      '/messages',
      data: jsonEncode(_body(messages, model, temperature, false)),
    );
    final data = resp.data!;
    final content = (data['content'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((c) => c['text'] as String? ?? '')
        .join();
    final usage = data['usage'] as Map<String, dynamic>?;
    return CompletionResult(
      text: content,
      promptTokens: (usage?['input_tokens'] as int?) ?? 0,
      completionTokens: (usage?['output_tokens'] as int?) ?? 0,
      model: data['model'] as String?,
    );
  }

  @override
  Stream<String> streamChat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) async* {
    final resp = await dio.post<ResponseBody>(
      '/messages',
      data: jsonEncode(_body(messages, model, temperature, true)),
      options: Options(responseType: ResponseType.stream),
    );
    final buf = StringBuffer();
    await for (final chunk in resp.data!.stream) {
      buf.write(utf8.decode(chunk, allowMalformed: true));
      final raw = buf.toString();
      // Anthropic sends SSE events separated by blank lines
      final blocks = raw.split('\n\n');
      buf.clear();
      buf.write(blocks.removeLast());
      for (final block in blocks) {
        for (final line in const LineSplitter().convert(block)) {
          if (!line.startsWith('data: ')) continue;
          try {
            final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            final t = json['type'] as String?;
            if (t == 'content_block_delta') {
              final delta = (json['delta'] as Map<String, dynamic>?)?['text'] as String?;
              if (delta != null && delta.isNotEmpty) yield delta;
            }
          } catch (_) {}
        }
      }
    }
  }

  Map<String, Object?> _body(List<ChatMsg> msgs, String? model,
      double temperature, bool stream) {
    final system = msgs.where((m) => m.role == 'system').map((m) => m.content).join('\n');
    final rest = msgs.where((m) => m.role != 'system').toList();
    return <String, Object?>{
      'model': model ?? config.models.last.id,
      'system': system.isEmpty ? null : system,
      'messages': [
        for (final m in rest)
          {'role': m.role == 'assistant' ? 'assistant' : 'user', 'content': m.content}
      ],
      'max_tokens': 8192,
      'temperature': temperature,
      'stream': stream,
    }..removeWhere((k, v) => v == null);
  }

  @override
  Future<List<double>?> embed(String text, {String? model}) async => null;
}