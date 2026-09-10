import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/provider.dart';

class ChatMsg {
  final String role; // system | user | assistant
  final String content;
  const ChatMsg(this.role, this.content);
}

class CompletionResult {
  final String text;
  final int promptTokens;
  final int completionTokens;
  final String? model;
  const CompletionResult({
    required this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.model,
  });
}

/// Contract implemented by every provider adapter.
abstract class ProviderClient {
  ProviderConfig get config;

  Stream<String> streamChat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  });

  Future<CompletionResult> chat(
    List<ChatMsg> messages, {
    String? model,
    double temperature = 0.7,
  });

  Future<List<double>?> embed(String text, {String? model});
}

/// Shared HTTP helpers for REST providers.
class HttpProviderBase {
  final Dio dio;
  HttpProviderBase({required String baseUrl, String? apiKey})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {
            if (apiKey != null) 'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
          responseType: ResponseType.stream,
        ));

  Stream<String> streamSse(String path, Map<String, Object?> body) async* {
    final resp = await dio.post<ResponseBody>(path, data: jsonEncode(body));
    await for (final chunk in resp.data!.stream) {
      final text = utf8.decode(chunk, allowMalformed: true);
      for (final line in const LineSplitter().convert(text)) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final delta = _extractDelta(json);
          if (delta != null && delta.isNotEmpty) yield delta;
        } catch (_) {
          // ignore partial
        }
      }
    }
  }

  static String? _extractDelta(Map<String, dynamic> json) {
    try {
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final first = choices.first as Map<String, dynamic>;
      final delta = first['delta'] as Map<String, dynamic>?;
      if (delta != null) return delta['content'] as String?;
      return first['text'] as String?;
    } catch (_) {
      return null;
    }
  }
}