import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/kb_document.dart';
import '../../services/database/database_service.dart';
import '../../widgets/common.dart';

/// D.B — Data Bank. Everything Pixel stores, browsable and searchable.
class DataBankTab extends StatefulWidget {
  final AppState state;
  const DataBankTab({super.key, required this.state});

  @override
  State<DataBankTab> createState() => _DataBankTabState();
}

class _DataBankTabState extends State<DataBankTab> {
  late Future<_DbSnapshot> _future;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DbSnapshot> _load() async {
    final db = widget.state.services.db;
    Future<List<Map<String, Object?>>> searchAll() async {
      if (_query.trim().length < 2) {
        final docs = await db.listKbDocuments();
        return docs.map((d) => {
              'title': d.title,
              'source': d.source.name,
              'kind': 'doc',
              'text': d.status,
              'uri': d.uri,
              'id': d.id,
            }).cast<Map<String, Object?>>().toList();
      }
      final results = await db.kbSearch(_query, limit: 30);
      return [
        for (final r in results)
          {
            'title': 'chunk #${r.index} (doc ${r.documentId})',
            'source': 'kb',
            'kind': 'chunk',
            'text': r.text,
            'uri': r.sourceRef,
            'id': r.id,
          }
      ].cast<Map<String, Object?>>();
    }

    final unifiedResults = _query.trim().length >= 2
        ? await db.unifiedSearch(_query)
        : <Map<String, Object?>>[];

    return _DbSnapshot(
      docs: await db.listKbDocuments(),
      hits: await searchAll(),
      unifiedResults: unifiedResults,
      usage: await db.usageStats(),
      providers: await db.listProviders(),
      settings: await db.getSettings(),
      skills: await db.listSkills(),
      models: await db.listTrainedModels(),
    );
  }

  Future<void> _deleteDoc(KbDocument d) async {
    await widget.state.services.db.deleteKbDocument(d.id!);
    await widget.state.refresh();
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DbSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _search,
              onChanged: (v) {
                _query = v;
                setState(() => _future = _load());
              },
              decoration: InputDecoration(
                hintText: 'Full-text search across everything…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _query = '';
                          setState(() => _future = _load());
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StatCard(
                  label: 'Messages',
                  value: '${d.usage['messages'] ?? 0}',
                  icon: Icons.chat,
                ),
                StatCard(
                  label: 'Tokens',
                  value:
                      '${((d.usage['promptTokens'] as int? ?? 0) + (d.usage['completionTokens'] as int? ?? 0))}',
                  icon: Icons.token,
                ),
                StatCard(
                  label: 'Documents',
                  value: '${d.docs.length}',
                  icon: Icons.description,
                ),
                StatCard(
                  label: 'Skills',
                  value: '${d.skills.length}',
                  icon: Icons.extension,
                ),
              ],
            ),
            const SectionHeader('Knowledge documents (L.B)'),
            if (d.docs.isEmpty)
              const EmptyState(
                  icon: Icons.description_outlined,
                  title: 'No documents',
                  message:
                      'Scrape sources in L.B, then they appear here and are '
                      'searchable from chat.')
            else
              ...d.docs.map((doc) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(_iconFor(doc.source),
                          color: AppColors.primaryLight),
                      title: Text(doc.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${doc.source.name} · ${doc.chunkCount} chunks · ${doc.status}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: AppColors.textLow),
                        onPressed: () async {
                          await _deleteDoc(doc);
                        },
                      ),
                    ),
                  )),
            const SectionHeader('Search results'),
            if (d.unifiedResults.isEmpty && d.hits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing matches.',
                    style: TextStyle(color: AppColors.textMid)),
              )
            else if (d.unifiedResults.isNotEmpty)
              ...d.unifiedResults.map((h) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                          _iconForSource(h['source_type'] as String),
                          size: 18,
                          color: _colorForSource(h['source_type'] as String)),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(h['title']!.toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _colorForSource(h['source_type'] as String)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                                (h['source_type'] as String).toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: _colorForSource(
                                        h['source_type'] as String))),
                          ),
                        ],
                      ),
                      subtitle: Text(
                          '${h['snippet']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ))
            else
              ...d.hits.map((h) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                          h['kind'] == 'chunk'
                              ? Icons.text_snippet_outlined
                              : Icons.source,
                          size: 18,
                          color: AppColors.accent),
                      title: Text(h['title']!.toString(),
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                          '${h['text']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  )),
            const SectionHeader('Smart routing & settings'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Level: ${d.settings.securityLevel.toUpperCase()}',
                        style: const TextStyle(color: AppColors.textMid)),
                    Text('Routing: ${d.settings.routingMode.toUpperCase()}',
                        style: const TextStyle(color: AppColors.textMid)),
                    Text('Budget: \$${d.settings.monthlyBudgetUsd}/mo',
                        style: const TextStyle(color: AppColors.textMid)),
                    for (final p in d.providers)
                      Text(p.enabled ? '✓ ${p.name}' : '· ${p.name}',
                          style: TextStyle(
                              color: p.enabled ? AppColors.good : AppColors.textLow,
                              fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
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

  IconData _iconForSource(String s) => switch (s) {
        'message' => Icons.chat_bubble_outline,
        'skill' => Icons.extension,
        'feature' => Icons.widgets_outlined,
        'kb' => Icons.article_outlined,
        _ => Icons.help_outline,
      };

  Color _colorForSource(String s) => switch (s) {
        'message' => AppColors.accent,
        'skill' => AppColors.good,
        'feature' => Colors.amber,
        'kb' => AppColors.primaryLight,
        _ => AppColors.textMid,
      };
}

class _DbSnapshot {
  final List<KbDocument> docs;
  final List<Map<String, Object?>> hits;
  final List<Map<String, Object?>> unifiedResults;
  final Map<String, Object?> usage;
  final List<dynamic> providers;
  final AppSettings settings;
  final List<dynamic> skills;
  final List<dynamic> models;
  const _DbSnapshot({
    required this.docs,
    required this.hits,
    required this.unifiedResults,
    required this.usage,
    required this.providers,
    required this.settings,
    required this.skills,
    required this.models,
  });
}