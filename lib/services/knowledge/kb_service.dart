import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../../models/kb_document.dart';
import '../../models/provider.dart';
import '../../models/security_event.dart';
import '../database/database_service.dart';
import '../providers/openai_provider.dart';
import '../providers/provider_client.dart';
import '../security/security_gateway.dart';

/// L.B — Live Brain. Ingests raw data from many sources into a local,
/// queryable knowledge base. Supports URL, PDF, text, RSS and, via the
/// provider vision/audio models, images and audio. Every source is scanned
/// by G.B on the way in before it is chunked or stored.
class KbService {
  final DatabaseService db;
  final SecurityGateway gateway;
  final Dio _http = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 90),
    headers: {'User-Agent': 'Pixel/0.1 (personal AI harness)'},
  ));

  KbService({required this.db, required this.gateway});

  Future<KbDocument> ingest({
    required KbSourceType type,
    String? uri,
    String? rawText,
    List<int>? bytes,
    String? title,
  }) async {
    final now = DateTime.now();
    final fallbackTitle = type == KbSourceType.text
        ? _firstLine(rawText ?? 'Untitled')
        : ((uri == null || uri.trim().isEmpty) ? 'Untitled' : uri).toString();
    final doc = KbDocument(
      source: type,
      title: (title == null || title.trim().isEmpty)
          ? fallbackTitle
          : title,
      uri: uri,
      mimeType: _mimeFor(type),
      createdAt: now,
    );
    final id = await db.insertKbDocument(doc);
    final saved = doc.copyWith(id: id);

    try {
      final sourceBytes = bytes ??
          (type == KbSourceType.pdf ? await _readFile(uri) : null);
      if (sourceBytes != null) await _gateBytes(sourceBytes, type);

      final text = switch (type) {
        KbSourceType.text => rawText ?? '',
        KbSourceType.url => await _fetchUrl(uri!),
        KbSourceType.pdf => await _extractPdf(sourceBytes!),
        KbSourceType.image =>
          await _visionText(uri: uri, bytes: sourceBytes ?? bytes),
        KbSourceType.audio =>
          await _audioText(uri: uri, bytes: sourceBytes ?? bytes),
        KbSourceType.video => await _transcriptVideo(uri!),
        KbSourceType.rss => await _fetchRss(uri!),
      };

      final cleanText = await _gateText(text, type);
      final clean = chunkText(cleanText, maxLen: 900, overlap: 120);
      final kbChunks = <KbChunk>[
        for (var i = 0; i < clean.length; i++)
          KbChunk(documentId: id, index: i, text: clean[i], sourceRef: uri),
      ];
      await db.insertKbChunks(kbChunks);
      final ready = saved.copyWith(status: 'ready', chunkCount: clean.length);
      await db.updateKbDocument(ready);
      return ready;
    } catch (e) {
      final failed = saved.copyWith(status: 'failed', error: e.toString());
      await db.updateKbDocument(failed);
      rethrow;
    }
  }

  /// G.B inbound choke point for raw byte payloads (malware containers).
  Future<void> _gateBytes(List<int> bytes, KbSourceType type) async {
    final scanned = await gateway.scanInbound(
      text: '',
      route: 'KB:L.B:${type.name}:bytes',
      fileBytes: bytes,
    );
    if (scanned.blocked) {
      throw StateError(_blockReason(scanned.events));
    }
  }

  /// G.B inbound choke point for extracted text: injection / sensitive /
  /// harmful-content scans abort the ingest so nothing suspicious reaches
  /// the knowledge base, and the payload is quarantined by the gateway.
  Future<String> _gateText(String text, KbSourceType type) async {
    final scanned = await gateway.scanInbound(
      text: text,
      route: 'KB:L.B:${type.name}',
    );
    if (scanned.blocked) {
      throw StateError(_blockReason(scanned.events));
    }
    return scanned.sanitized;
  }

  String _blockReason(List<SecurityEvent> events) {
    if (events.isEmpty) return 'Content blocked by G.B';
    final first = events.first;
    return 'Content blocked by G.B: ${first.category.name} - ${first.summary}';
  }

  Future<List<int>> _readFile(String? uri) async {
    if (uri == null) throw ArgumentError('file path required');
    return File(uri).readAsBytes();
  }

  Future<String> _fetchUrl(String url) async {
    final resp = await _http.get<String>(url);
    final doc = html_parser.parse(resp.data ?? '');
    doc
        .querySelectorAll('script, style, noscript, header, footer, nav')
        .forEach((e) => e.remove());
    return _clean(doc.body?.text ?? '');
  }

  // ---- PDF (text-based PDFs; no native deps, flate + Tj/TJ operators) ----
  Future<String> _extractPdf(List<int> bytes) async {
    final decoder = ZLibDecoder();
    final text = latin1.decode(bytes, allowInvalid: true);
    final re = RegExp(r'stream\r?\n(.*?)endstream', dotAll: true);
    final parts = <String>[];
    for (final m in re.allMatches(text)) {
      final raw = _latin1Bytes(m.group(1)!);
      try {
        parts.add(_extractPdfText(decoder.convert(raw)));
      } catch (_) {
        parts.add(_extractPdfText(raw));
      }
    }
    final joined = parts.join(' ');
    if (joined.trim().isEmpty) {
      throw StateError(
          'No extractable text found. Scanned PDFs should be re-ingested as '
          'images for OCR.');
    }
    return _clean(joined);
  }

  List<int> _latin1Bytes(String s) {
    final out = <int>[];
    for (final c in s.runes) {
      out.add(c <= 255 ? c : 63);
    }
    return out;
  }

  String _extractPdfText(List<int> bytes) {
    final re = RegExp(
        r'\((?:[^()\\]|\\.)*\)\s*Tj|'
        r'TJ(?:\[(?:\((?:[^()\\]|\\.)*\)|-?\d+\.?\d*|[^\])])*,)?');
    final s = latin1.decode(bytes, allowInvalid: true);
    final out = StringBuffer();
    for (final m in re.allMatches(s)) {
      final inner = m.group(0)!;
      if (inner.startsWith('TJ')) {
        out.write(_pdfTjText(inner));
      } else {
        out.write(_pdfLiteral(inner));
      }
      out.write(' ');
    }
    return out.toString();
  }

  String _pdfTjText(String tj) {
    final buf = StringBuffer();
    final re = RegExp(r'\((?:[^()\\]|\\.)*\)');
    for (final lit in re.allMatches(tj)) {
      buf.write(_pdfLiteral(lit.group(0)!));
    }
    return buf.toString();
  }

  String _pdfLiteral(String lit) {
    var inner = lit.substring(1, lit.length - 1);
    inner = inner.replaceAll(r'\n', ' ').replaceAll(r'\r', ' ');
    inner = inner.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
    inner = inner.replaceAll(r'\\(', '(').replaceAll(r'\\)', ')');
    return inner;
  }

  // ---- RSS ----
  Future<String> _fetchRss(String url) async {
    final resp = await _http.get<String>(url);
    final doc = XmlDocument.parse(resp.data ?? '');
    final items = doc.findAllElements('item');
    final out = <String>[];
    for (final it in items) {
      final t = it.getElement('title')?.innerText ?? '';
      final link = it.getElement('link')?.innerText ?? '';
      final desc = it.getElement('description')?.innerText ??
          it.getElement('encoded')?.innerText ??
          '';
      out.add('## $t\n$link\n\n${_clean(desc)}');
      if (out.length >= 30) break;
    }
    if (out.isEmpty) throw StateError('No RSS items found at $url');
    return out.join('\n\n---\n\n');
  }

  // ---- Vision (image OCR) via Gemini or GPT-4o ----
  Future<String> _visionText({String? uri, List<int>? bytes}) async {
    final providers = await db.listProviders();
    ProviderConfig? gemini;
    ProviderConfig? openai;
    for (final p in providers) {
      if (p.kind == ProviderKind.google && p.apiKey?.isNotEmpty == true) {
        gemini = p;
      } else if (p.id == 'openai' && p.apiKey?.isNotEmpty == true) {
        openai = p;
      }
    }
    final p = gemini ?? openai;
    if (p == null) {
      throw StateError(
          'OCR requires a Gemini or OpenAI API key configured in G.B/settings.');
    }
    if (p == gemini) return _geminiMedia(p, bytes, uri, 'image');
    return _openAiVision(p, bytes, uri);
  }

  Future<String> _audioText({String? uri, List<int>? bytes}) async {
    final providers = await db.listProviders();
    final p = providers.where((c) => c.kind == ProviderKind.google &&
            c.apiKey?.isNotEmpty == true)
        .firstOrNull;
    if (p == null) {
      throw StateError(
          'Audio transcription requires a Gemini API key configured in settings.');
    }
    return _geminiMedia(p, bytes, uri, 'audio');
  }

  Future<String> _geminiMedia(
      ProviderConfig p, List<int>? bytes, String? uri, String kind) async {
    final data = (bytes ??
            (await _http.get<List<int>>(uri!,
                options: Options(responseType: ResponseType.bytes)))
                .data) ??
        const <int>[];
    final mime = kind == 'audio'
        ? (uri?.toLowerCase().endsWith('.mp3') ?? false ? 'audio/mpeg' : 'audio/wav')
        : (uri?.toLowerCase().endsWith('.png') ?? false ? 'image/png' : 'image/jpeg');
    final prompt = kind == 'audio'
        ? 'Transcribe this audio verbatim.'
        : 'Extract all text from this image verbatim.';
    final resp = await _http.post<Map<String, dynamic>>(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent',
      queryParameters: {'key': p.apiKey},
      data: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {'inline_data': {'mime_type': mime, 'data': base64Encode(data)}},
            ]
          }
        ]
      }),
    );
    final parts = (resp.data!['candidates'] as List? ?? [])
        .firstOrNull?['content']?['parts'] as List? ?? [];
    return parts
        .map((x) => (x as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
  }

  Future<String> _openAiVision(ProviderConfig p, List<int>? bytes, String? uri) async {
    final data = (bytes ??
            (await _http.get<List<int>>(uri!,
                options: Options(responseType: ResponseType.bytes)))
                .data) ??
        const <int>[];
    final mime =
        (uri?.toLowerCase().endsWith('.png') ?? false) ? 'image/png' : 'image/jpeg';
    final client = OpenAIProvider(config: p);
    final resp = await client.chat([
      const ChatMsg('user',
          'Extract all text from the attached image verbatim. Return only the '
          'extracted text.'),
    ]);
    // retry with image inline if supported by the model
    final text = resp.text;
    if (text.isNotEmpty) return text;
    final r2 = await client.chat([
      ChatMsg('user',
          'OCR the image (data:$mime;base64,${base64Encode(data)}) and return the text.'),
    ]);
    return r2.text;
  }

  Future<String> _transcriptVideo(String uri) async {
    if (uri.contains('youtube.com') || uri.contains('youtu.be')) {
      final id = _youtubeId(uri);
      if (id != null) {
        try {
          final resp = await _http.get<String>(
              'https://www.youtube.com/api/timedtext?lang=en&v=$id');
          final trimmed = _clean(resp.data ?? '');
          if (trimmed.isNotEmpty) return trimmed;
        } catch (_) {}
        throw StateError(
            'No accessible English captions for this video via timedtext.');
      }
    }
    throw StateError(
        'Only YouTube captions are auto-extractable today. For other videos, '
        'ingest a transcript file as a text source.');
  }

  String? _youtubeId(String url) {
    final re =
        RegExp(r'(?:v=|youtu\.be/|shorts/|embed/)([\w-]{11})');
    return re.firstMatch(url)?.group(1);
  }

  String _mimeFor(KbSourceType t) => switch (t) {
        KbSourceType.text => 'text/plain',
        KbSourceType.url => 'text/html',
        KbSourceType.pdf => 'application/pdf',
        KbSourceType.image => 'image/*',
        KbSourceType.video => 'video/*',
        KbSourceType.audio => 'audio/*',
        KbSourceType.rss => 'application/rss+xml',
      };

  String _firstLine(String s) {
    final i = s.indexOf('\n');
    return (i < 0 ? s : s.substring(0, i)).trim();
  }

  String _clean(String s) => s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static List<String> chunkText(String text,
      {int maxLen = 900, int overlap = 120}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return ['[empty document]'];
    final chunks = <String>[];
    var start = 0;
    while (start < clean.length && chunks.length < 10000) {
      var end = start + maxLen;
      if (end >= clean.length) {
        end = clean.length;
      } else {
        final lastSpace = clean.lastIndexOf(' ', end);
        if (lastSpace > start + maxLen ~/ 2) end = lastSpace;
      }
      chunks.add((clean.substring(start, end)).trim());
      final next = end - overlap;
      if (next <= start) break;
      start = next;
    }
    return chunks;
  }

  Future<List<KbChunk>> search(String query, {int limit = 10}) async {
    return db.kbSearch(query, limit: limit);
  }

  Future<void> embedAll({ProviderConfig? provider}) async {
    final embProvider = provider ??
        (await db.listProviders())
            .where((p) => p.id == 'openai' && p.apiKey?.isNotEmpty == true)
            .firstOrNull;
    if (embProvider == null) return;
    final embedder = _OpenAiEmbedder(embProvider);
    final docs = await db.listKbDocuments();
    for (final doc in docs) {
      final chunks = await db.kbChunksForDoc(doc.id!);
      for (final c in chunks) {
        if (c.embedding.isNotEmpty) continue;
        final vec = await embedder.embed(c.text);
        if (vec != null) {
          await db.db.update('kb_chunks', {
            'embedding': vec.map((v) => v.toStringAsFixed(6)).join(',')
          }, where: 'id = ?', whereArgs: [c.id]);
        }
      }
    }
  }

  /// Semantic search over provider-embedded chunks with FTS5 fallback.
  Future<List<KbChunk>> semanticSearch(String query, {int limit = 8}) async {
    final embProvider = (await db.listProviders())
        .where((p) => p.id == 'openai' && p.apiKey?.isNotEmpty == true)
        .firstOrNull;
    final all = await db.allKbChunks(limit: 2000);
    if (embProvider == null) {
      // no embeddings: semantic terms may still hit FTS5; do a term expansion
      return db.kbSearch(query, limit: limit);
    }
    final q = await _OpenAiEmbedder(embProvider).embed(query);
    if (q == null) return db.kbSearch(query, limit: limit);
    final scored = <(double, KbChunk)>[];
    for (final c in all) {
      if (c.embedding.length != q.length) continue;
      scored.add((_cosine(q, c.embedding), c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(limit).map((e) => e.$2).toList();
  }

  static double _cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }
}

class _OpenAiEmbedder {
  final ProviderConfig config;
  _OpenAiEmbedder(this.config);

  Future<List<double>?> embed(String text) =>
      OpenAIProvider(config: config).embed(text);
}