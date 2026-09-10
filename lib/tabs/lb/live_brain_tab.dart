import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/kb_document.dart';
import '../../widgets/common.dart';

/// L.B — Live Brain. Scrape raw data from links, PDFs, text, images, audio,
/// videos and RSS into the local knowledge base.
class LiveBrainTab extends StatefulWidget {
  final AppState state;
  const LiveBrainTab({super.key, required this.state});

  @override
  State<LiveBrainTab> createState() => _LiveBrainTabState();
}

class _LiveBrainTabState extends State<LiveBrainTab> {
  late Future<_LbSnapshot> _future;
  final TextEditingController _uri = TextEditingController();
  final TextEditingController _text = TextEditingController();
  KbSourceType _type = KbSourceType.url;
  bool _busy = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LbSnapshot> _load() async {
    final db = widget.state.services.db;
    return _LbSnapshot(
      docs: await db.listKbDocuments(),
      hits: await db.kbSearch(''),
    );
  }

  Future<void> _ingest() async {
    final kb = widget.state.services.kb;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      KbSourceType src = _type;
      String? uri = _uri.text.trim();
      String? rawText;
      List<int>? bytes;
      String? title;

      if (_type == KbSourceType.url || _type == KbSourceType.rss ||
          _type == KbSourceType.video) {
        if (uri.isEmpty) throw StateError('Enter a URL.');
      } else if (_type == KbSourceType.text) {
        rawText = _text.text;
        if (rawText.trim().isEmpty) throw StateError('Enter some text.');
      } else {
        // image / audio / pdf selected via queue below
      }

      await kb.ingest(type: src, uri: uri, rawText: rawText,
          bytes: bytes, title: title);
      _uri.clear();
      _text.clear();
      setState(() {
        _feedback = 'Document ingested into the knowledge base.';
        _future = _load();
      });
      widget.state.services.db.kbSearch(''); // warm fts
    } catch (e) {
      setState(() => _feedback = 'Ingest failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: _type == KbSourceType.pdf ? FileType.custom : FileType.any,
      allowedExtensions: _type == KbSourceType.pdf ? ['pdf'] : null,
    );
    final f = result?.files.firstOrNull;
    if (f == null) return;
    final bytes = f.bytes;
    if (bytes == null) {
      setState(() => _feedback = 'File bytes unavailable on this platform.');
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await widget.state.services.kb.ingest(
        type: _type,
        bytes: bytes,
        title: f.name,
        uri: f.name,
      );
      setState(() {
        _feedback = 'File ingested (${f.name}).';
        _future = _load();
      });
    } catch (e) {
      setState(() => _feedback = 'Ingest failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  IconData _iconFor(KbSourceType t) => switch (t) {
        KbSourceType.url => Icons.link,
        KbSourceType.pdf => Icons.picture_as_pdf_outlined,
        KbSourceType.image => Icons.image_outlined,
        KbSourceType.audio => Icons.headphones_outlined,
        KbSourceType.video => Icons.videocam_outlined,
        KbSourceType.text => Icons.notes,
        KbSourceType.rss => Icons.rss_feed,
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LbSnapshot>(
      future: _future,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const <KbDocument>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('SCRAPER',
                style: TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            const Text(
                'Ingest raw data from links, files and text. Everything lands '
                'in D.B and is queryable from MI.B.',
                style: TextStyle(color: AppColors.textMid, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final t in KbSourceType.values)
                  ChoiceChip(
                    label: Text(t.name),
                    selected: _type == t,
                    onSelected: (_) =>
                        setState(() { _type = t; _uri.clear(); _text.clear(); }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_type == KbSourceType.url ||
                _type == KbSourceType.rss ||
                _type == KbSourceType.video) ...[
              TextField(
                controller: _uri,
                decoration: InputDecoration(
                  hintText: _type == KbSourceType.rss
                      ? 'https://example.com/feed.xml'
                      : _type == KbSourceType.video
                          ? 'YouTube URL to capture captions'
                          : 'https://…',
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 8),
              PixelButton(
                label: 'Scrape',
                icon: Icons.download,
                busy: _busy,
                onPressed: _ingest,
              ),
            ] else if (_type == KbSourceType.text) ...[
              TextField(
                controller: _text,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Paste raw text, notes or a transcript…',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 8),
              PixelButton(
                label: 'Ingest text',
                icon: Icons.save_alt,
                busy: _busy,
                onPressed: _ingest,
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: PixelButton(
                      label: 'Pick ${_type.name} file',
                      icon: Icons.upload_file,
                      busy: _busy,
                      onPressed: _pickFile,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                  _type == KbSourceType.image
                      ? 'Image OCR uses the Gemini or GPT-4o provider key.'
                      : _type == KbSourceType.audio
                          ? 'Audio transcription uses the Gemini provider key.'
                          : 'PDF text extraction runs entirely on-device.',
                  style: const TextStyle(color: AppColors.textLow, fontSize: 11)),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 10),
              Text(_feedback!,
                  style: const TextStyle(
                      color: AppColors.accent, fontSize: 12)),
            ],
            const SectionHeader('Knowledge base'),
            if (docs.isEmpty)
              const EmptyState(
                  icon: Icons.psychology_outlined,
                  title: 'No data yet',
                  message:
                      'Whatever you scrape becomes context Pixel can use in chat '
                      'and skills. Ask it: "summarize my newest document".')
            else
              ...docs.map((d) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(_iconFor(d.source),
                          color: d.status == 'ready'
                              ? AppColors.good
                              : d.status == 'failed'
                                  ? AppColors.bad
                                  : AppColors.warn),
                      title: Text(d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${d.source.name} · ${d.chunkCount} chunks · ${d.status}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: AppColors.textLow),
                        onPressed: () async {
                          await widget.state.services.db
                              .deleteKbDocument(d.id!);
                          setState(() => _future = _load());
                        },
                      ),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _LbSnapshot {
  final List<KbDocument> docs;
  final List hits;
  const _LbSnapshot({required this.docs, required this.hits});
}