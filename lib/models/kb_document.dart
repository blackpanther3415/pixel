enum KbSourceType { url, pdf, image, audio, video, text, rss }

class KbDocument {
  final int? id;
  final KbSourceType source;
  final String title;
  final String? uri;
  final String? rawPath;
  final String mimeType;
  final String status; // 'processing' | 'ready' | 'failed'
  final String? error;
  final int chunkCount;
  final DateTime createdAt;

  const KbDocument({
    this.id,
    required this.source,
    required this.title,
    this.uri,
    this.rawPath,
    required this.mimeType,
    this.status = 'processing',
    this.error,
    this.chunkCount = 0,
    required this.createdAt,
  });

  KbDocument copyWith({
    int? id,
    String? title,
    String? uri,
    String? rawPath,
    String? status,
    String? error,
    int? chunkCount,
  }) =>
      KbDocument(
        id: id ?? this.id,
        source: source,
        title: title ?? this.title,
        uri: uri ?? this.uri,
        rawPath: rawPath ?? this.rawPath,
        mimeType: mimeType,
        status: status ?? this.status,
        error: error ?? this.error,
        chunkCount: chunkCount ?? this.chunkCount,
        createdAt: createdAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'source': source.name,
        'title': title,
        'uri': uri,
        'raw_path': rawPath,
        'mime': mimeType,
        'status': status,
        'error': error,
        'chunks': chunkCount,
        'created_at': createdAt.toIso8601String(),
      };

  factory KbDocument.fromDb(Map<String, Object?> m) => KbDocument(
        id: m['id'] as int?,
        source: KbSourceType.values.firstWhere(
            (s) => s.name == m['source'],
            orElse: () => KbSourceType.text),
        title: (m['title'] as String?) ?? 'Untitled',
        uri: m['uri'] as String?,
        rawPath: m['raw_path'] as String?,
        mimeType: (m['mime'] as String?) ?? 'text/plain',
        status: (m['status'] as String?) ?? 'processing',
        error: m['error'] as String?,
        chunkCount: (m['chunks'] as int?) ?? 0,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.now(),
      );
}

class KbChunk {
  final int id;
  final int documentId;
  final int index;
  final String text;
  final List<double> embedding;
  final String? sourceRef;

  const KbChunk({
    this.id = 0,
    required this.documentId,
    required this.index,
    required this.text,
    this.embedding = const [],
    this.sourceRef,
  });

  Map<String, Object?> toDb() => {
        'doc_id': documentId,
        'idx': index,
        'text': text,
        'embedding': embedding.isEmpty
            ? null
            : embedding.map((v) => v.toStringAsFixed(6)).join(','),
        'source_ref': sourceRef,
      };

  factory KbChunk.fromDb(Map<String, Object?> m) => KbChunk(
        id: m['id'] as int,
        documentId: m['doc_id'] as int,
        index: (m['idx'] as int?) ?? 0,
        text: (m['text'] as String?) ?? '',
        embedding: (m['embedding'] as String?)
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => double.tryParse(s.trim()) ?? 0)
            .toList() ??
            const [],
        sourceRef: m['source_ref'] as String?,
      );
}