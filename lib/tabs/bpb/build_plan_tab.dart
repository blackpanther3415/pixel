import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../services/builder/plan_build_service.dart';
import '../../models/skill.dart';
import '../../widgets/common.dart';

/// B/P.B — Build & Plan. Mirrors a planning session: describe a feature,
/// Pixel drafts a plan, you approve, it builds a runnable skill, then T.B
/// tests it.
class BuildPlanTab extends StatefulWidget {
  final AppState state;
  const BuildPlanTab({super.key, required this.state});

  @override
  State<BuildPlanTab> createState() => _BuildPlanTabState();
}

class _BuildPlanTabState extends State<BuildPlanTab> {
  final TextEditingController _desc = TextEditingController();
  BuildPlan? _plan;
  bool _busy = false;
  String? _feedback;
  Skill? _built;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    final text = _desc.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _feedback = 'Pixel is planning…';
      _built = null;
    });
    try {
      final plan = await widget.state.services.builder.draftPlan(text);
      setState(() {
        _plan = plan;
        _busy = false;
        _feedback = 'Plan drafted. Review it and approve to build.';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = 'Plan failed: $e';
      });
    }
  }

  Future<void> _approve() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _busy = true);
    try {
      final skill = await widget.state.services.builder.buildFromPlan(plan);
      setState(() {
        _built = skill;
        _busy = false;
        _feedback =
            'Built "${skill.name}". Test it in T.B, then approve into F.B.';
      });
      await widget.state.refresh();
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = 'Build failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('B/P.B · BUILD & PLAN',
            style: TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5)),
        const SizedBox(height: 4),
        const Text(
            'Describe a new feature. Pixel plans it with you step by step — '
            'then bends it into a runnable skill on approval. Plan → Approve '
            '→ Build → Test.',
            style: TextStyle(color: AppColors.textMid, fontSize: 12)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _desc,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText:
                        'Describe the feature you want to build\n'
                        'e.g. "A weekly digest that summarizes my RSS feeds '
                        'and surfaces the 3 most important items."',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    PixelButton(
                      label: 'Draft plan',
                      icon: Icons.psychology,
                      busy: _busy,
                      onPressed: _draft,
                    ),
                    if (_plan != null)
                      PixelButton(
                        label: 'Approve & build',
                        icon: Icons.hardware,
                        color: AppColors.good,
                        busy: _busy,
                        onPressed: _approve,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_feedback != null) ...[
          const SizedBox(height: 10),
          Text(_feedback!,
              style:
                  const TextStyle(color: AppColors.accent, fontSize: 13)),
        ],
        if (_plan != null) ...[
          const SectionHeader('Approval — review the plan'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_plan!.title,
                      style: const TextStyle(
                          color: AppColors.textHigh,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_plan!.summary,
                      style: const TextStyle(color: AppColors.textMid)),
                  const SizedBox(height: 12),
                  for (final (i, s) in _plan!.steps.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: AppColors.primary,
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.title,
                                    style: const TextStyle(
                                        color: AppColors.textHigh,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                if (s.details.isNotEmpty)
                                  Text(s.details,
                                      style: const TextStyle(
                                          color: AppColors.textMid,
                                          fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_plan!.risks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Risks',
                        style: TextStyle(
                            color: AppColors.warn, fontWeight: FontWeight.w600)),
                    for (final r in _plan!.risks)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $r',
                            style: const TextStyle(
                                color: AppColors.textMid, fontSize: 12)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (_built != null) ...[
          const SectionHeader('Built artifact'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.extension,
                  color: AppColors.primaryLight),
              title: Text(_built!.name,
                  style: const TextStyle(
                      color: AppColors.textHigh,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${_built!.type.name} skill · status ${_built!.status.name} · '
                  'safety ${_built!.safetyScore}/100'),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textLow),
            ),
          ),
        ],
      ],
    );
  }
}