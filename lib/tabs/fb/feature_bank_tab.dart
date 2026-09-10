import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/feature.dart';
import '../../models/skill.dart';
import '../../widgets/common.dart';

/// F.B — Feature Bank. The library of everything Pixel can do. Browse,
/// enable/disable, favorite, inspect safety ratings, trigger shortcuts.
class FeatureBankTab extends StatefulWidget {
  final AppState state;
  const FeatureBankTab({super.key, required this.state});

  @override
  State<FeatureBankTab> createState() => _FeatureBankTabState();
}

class _FeatureBankTabState extends State<FeatureBankTab> {
  late Future<List<Feature>> _features;
  late Future<List<Skill>> _skills;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final db = widget.state.services.db;
    _features = db.listFeatures();
    _skills = db.listSkills();
  }

  Future<void> _toggle(Feature f) async {
    await widget.state.services.db
        .upsertFeature(f.copyWith(enabled: !f.enabled));
    setState(_load);
    await widget.state.refresh();
  }

  Future<void> _favorite(Feature f) async {
    await widget.state.services.db
        .upsertFeature(f.copyWith(favorite: !f.favorite));
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Feature>>(
      future: _features,
      builder: (context, snap) {
        final all = snap.data ?? const <Feature>[];
        final filtered = _filter == 'all'
            ? all
            : all.where((f) => f.enabled == (_filter == 'active')).toList()
              .where((f) => _filter == 'active'
                  ? f.enabled
                  : !f.enabled || true)
              .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('F.B · FEATURE BANK',
                style: TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            const Text(
                'Every feature — built-in, built, or cloned — lives here. '
                'Enable what you use; Pixel creates quick shortcuts.',
                style: TextStyle(color: AppColors.textMid, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final f in ['all', 'active', 'inactive'])
                  ChoiceChip(
                    label: Text(f),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            const SectionHeader('Library'),
            if (filtered.isEmpty)
              const EmptyState(
                  icon: Icons.extension_outlined,
                  title: 'Library is empty',
                  message:
                      'Build features in B/P.B, clone tools in C.B or train '
                      'models in LLM — they appear here automatically.')
            else
              ...filtered.map((f) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                          f.enabled ? Icons.extension : Icons.extension_off,
                          color: f.enabled ? AppColors.good : AppColors.textLow),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(f.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.textHigh,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (f.favorite)
                            const Icon(Icons.star,
                                size: 14, color: AppColors.warn),
                        ],
                      ),
                      subtitle: Text(
                          '${f.source.name} · safety ${f.safetyScore}/100 · '
                          'used ${f.usageCount}x${f.shortcutTarget != null ? " · → ${f.shortcutTarget}" : ""}',
                          style: const TextStyle(fontSize: 11)),
                      onTap: () => _toggle(f),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                                f.favorite ? Icons.star : Icons.star_border,
                                size: 18),
                            onPressed: () => _favorite(f),
                          ),
                          Switch(
                            value: f.enabled,
                            onChanged: (_) => _toggle(f),
                          ),
                        ],
                      ),
                    ),
                  )),
            const SectionHeader('Installed skills'),
            FutureBuilder<List<Skill>>(
              future: _skills,
              builder: (context, sSnap) {
                final skills = sSnap.data ?? const <Skill>[];
                if (skills.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No skills installed yet.',
                        style: TextStyle(color: AppColors.textMid)),
                  );
                }
                return Column(
                  children: [
                    for (final s in skills)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.bolt,
                              size: 18, color: AppColors.primaryLight),
                          title: Text(s.name,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              '${s.type.name} · ${s.status.name} · safety ${s.safetyScore}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(s.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textLow, fontSize: 11)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}