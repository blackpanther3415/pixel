import 'dart:convert';

import '../../models/feature.dart';
import '../../models/provider.dart';
import '../../models/skill.dart';
import '../database/database_service.dart';
import '../providers/provider_client.dart';
import '../providers/provider_factory.dart';

/// B/P.B — Build & Plan. Mirrors this very session: user dictates a feature,
/// Pixel drafts a plan, the user approves, Pixel generates the buildable
/// artifact (a skill graph + CS.B flow + feature entry), then T.B tests it.
class PlanBuildService {
  final DatabaseService db;

  PlanBuildService({required this.db});

  /// Step 1: draft plan from feature description.
  Future<BuildPlan> draftPlan(String featureDescription) async {
    final provider = await _pickProvider();
    if (provider == null) {
      throw StateError('B/P.B needs an AI provider with an API key configured.');
    }
    final client = ProviderFactory.create(provider);
    final res = await client.chat([
      const ChatMsg('system',
          'You are the lead planner of the Pixel AI harness. Produce '
              'concise, truthful, realistic engineering plans. No fluff.'),
      ChatMsg('user',
          'Feature request: $featureDescription\n\n'
              'Produce a plan as JSON with exactly:\n'
              '{"title": string, "summary": string, '
              '"steps": [{"title": string, "details": string}], '
              '"risks": [string], "buildable_skill": '
              '{"id": string, "name": string, "description": string, '
              '"steps": [{"name": string, "type": "prompt|provider|condition|concatenate|extract", '
              '"params": {}}]} }\n\n'
              'The buildable_skill must be a valid Pixel no-code skill and '
              'must be directly runnable. Output ONLY JSON.'),
    ]);
    return BuildPlan.fromJson(res.text);
  }

  /// Step 2: user-approved plan -> generate artifact + feature entry.
  Future<Skill> buildFromPlan(BuildPlan plan) async {
    final now = DateTime.now();
    final spec = plan.buildableSkill;
    if (spec == null || spec['steps'] is! List) {
      throw StateError('Plan has no buildable skill. Ask Pixel to revise.');
    }
    final skill = Skill(
      id: (spec['id'] as String?) ?? 'bp-${now.millisecondsSinceEpoch}',
      name: (spec['name'] as String?) ?? plan.title,
      description: (spec['description'] as String?) ?? plan.summary,
      type: SkillType.noCode,
      status: SkillStatus.draft,
      graphJson: jsonEncode(spec),
      createdAt: now,
      updatedAt: now,
    );
    await db.upsertSkill(skill);
    await db.upsertFeature(Feature.create(
      name: skill.name,
      description: skill.description,
      source: FeatureSource.built,
      safetyScore: 75,
      enabled: false,
      shortcutTarget: 'mib',
    ));
    return skill;
  }

  Future<ProviderConfig?> _pickProvider() async {
    final provs = await db.listProviders();
    for (final p in provs) {
      if (p.enabled && p.apiKey?.isNotEmpty == true) return p;
    }
    return null;
  }
}

class BuildPlan {
  final String title;
  final String summary;
  final List<PlanStep> steps;
  final List<String> risks;
  final Map<String, dynamic>? buildableSkill;

  const BuildPlan({
    required this.title,
    required this.summary,
    required this.steps,
    required this.risks,
    this.buildableSkill,
  });

  factory BuildPlan.fromJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    Map<String, dynamic> m = const {};
    if (start >= 0 && end > start) {
      try {
        m = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      } catch (_) {
        m = const {};
      }
    }
    return BuildPlan(
      title: (m['title'] as String?) ?? 'Draft plan',
      summary: (m['summary'] as String?) ?? '',
      steps: [
        for (final s in (m['steps'] as List? ?? []))
          PlanStep(
            title: ((s as Map<String, dynamic>)['title'] as String?) ?? '',
            details: (s['details'] as String?) ?? '',
          )
      ],
      risks: [
        for (final r in (m['risks'] as List? ?? [])) r.toString()
      ],
      buildableSkill:
          m['buildable_skill'] as Map<String, dynamic>?,
    );
  }
}

class PlanStep {
  final String title;
  final String details;
  const PlanStep({required this.title, required this.details});
}