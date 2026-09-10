import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/provider.dart';
import 'provider_client.dart';

/// Local Ollama server (OpenAI-compatible /chat/completions endpoint too).
class OllamaProvider implements ProviderClient {
  @override
  final ProviderConfig config;
  final Dio dio;

  OllamaProvider({required this.config})
      : dio = Dio(BaseOptions(
          baseUrl: config.baseUrl ?? 'http://localhost:11434',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 300),
        ));

  Future<bool> ping() async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/api/tags');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CompletionResult> chat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) async {
    final resp = await dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: jsonEncode({
        'model': model ?? config.models.last.id,
        'messages': [
          for (final m in messages) {'role': m.role, 'content': m.content}
        ],
        'stream': false,
        'options': {'temperature': temperature},
      }),
    );
    final data = resp.data!;
    return CompletionResult(
      text: (data['message'] as Map<String, dynamic>?)?['content'] as String? ?? '',
      promptTokens: (data['prompt_eval_count'] as int?) ?? 0,
      completionTokens: (data['eval_count'] as int?) ?? 0,
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
      '/api/chat',
      data: jsonEncode({
        'model': model ?? config.models.last.id,
        'messages': [
          for (final m in messages) {'role': m.role, 'content': m.content}
        ],
        'stream': true,
        'options': {'temperature': temperature},
      }),
      options: Options(responseType: ResponseType.stream),
    );
    final buf = StringBuffer();
    await for (final chunk in resp.data!.stream) {
      buf.write(utf8.decode(chunk, allowMalformed: true));
      final raw = buf.toString();
      final lines = const LineSplitter().convert(raw);
      if (lines.isNotEmpty && !raw.endsWith('\n')) {
        buf.clear();
        buf.write(lines.removeLast());
      } else {
        buf.clear();
      }
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final t = (json['message'] as Map<String, dynamic>?)?['content'] as String?;
          if (t != null && t.isNotEmpty) yield t;
        } catch (_) {}
      }
    }
    final tail = buf.toString();
    if (tail.trim().isNotEmpty) {
      try {
        final json = jsonDecode(tail) as Map<String, dynamic>;
        final t = (json['message'] as Map<String, dynamic>?)?['content'] as String?;
        if (t != null && t.isNotEmpty) yield t;
      } catch (_) {}
    }
  }

  @override
  Future<List<double>?> embed(String text, {String? model}) async => null;
}