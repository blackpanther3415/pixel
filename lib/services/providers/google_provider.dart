import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/provider.dart';
import 'provider_client.dart';

/// Google Gemini API (generateContent + streamGenerateContent).
class GoogleProvider implements ProviderClient {
  @override
  final ProviderConfig config;
  final Dio dio;

  GoogleProvider({required this.config})
      : dio = Dio(BaseOptions(
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        )) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      o.queryParameters['key'] = config.apiKey;
      h.next(o);
    }));
  }

  @override
  Future<CompletionResult> chat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) async {
    final m = model ?? config.models.last.id;
    final resp = await dio.post<Map<String, dynamic>>(
      '/models/$m:generateContent',
      data: jsonEncode(_body(messages, temperature)),
    );
    return _parse(resp.data!);
  }

  @override
  Stream<String> streamChat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  }) async* {
    final m = model ?? config.models.last.id;
    final resp = await dio.post<ResponseBody>(
      '/models/$m:streamGenerateContent',
      data: jsonEncode(_body(messages, temperature)),
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
          final parts = (json['candidates'] as List? ?? [])
              .firstOrNull?['content']?['parts'] as List?;
          for (final p in parts ?? <dynamic>[]) {
            final t = (p as Map<String, dynamic>)['text'] as String?;
            if (t != null && t.isNotEmpty) yield t;
          }
        } catch (_) {}
      }
    }
    final tail = buf.toString();
    if (tail.trim().isNotEmpty) {
      try {
        final json = jsonDecode(tail) as Map<String, dynamic>;
        final parts = (json['candidates'] as List? ?? [])
            .firstOrNull?['content']?['parts'] as List?;
        for (final p in parts ?? <dynamic>[]) {
          final t = (p as Map<String, dynamic>)['text'] as String?;
          if (t != null && t.isNotEmpty) yield t;
        }
      } catch (_) {}
    }
  }

  Map<String, Object?> _body(List<ChatMsg> msgs, double temperature) {
    final contents = <Map<String, Object?>>[];
    for (final m in msgs) {
      if (m.role == 'system') {
        contents.add({
          'role': 'user',
          'parts': [
            {'text': 'System instruction: ${m.content}'}
          ],
        });
      } else {
        contents.add({
          'role': m.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m.content}
          ],
        });
      }
    }
    return {
      'contents': contents,
      'generationConfig': {'temperature': temperature},
    };
  }

  CompletionResult _parse(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List? ?? [];
    final parts = candidates.firstOrNull?['content']?['parts'] as List? ?? [];
    final text = parts.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '').join();
    final meta = data['usageMetadata'] as Map<String, dynamic>?;
    return CompletionResult(
      text: text,
      promptTokens: (meta?['promptTokenCount'] as int?) ?? 0,
      completionTokens: (meta?['candidatesTokenCount'] as int?) ?? 0,
      model: data['modelVersion'] as String?,
    );
  }

  @override
  Future<List<double>?> embed(String text, {String? model}) async => null;
}