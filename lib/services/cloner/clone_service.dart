import 'dart:convert';

import '../../models/feature.dart';
import '../../models/provider.dart';
import '../../models/skill.dart';
import '../database/database_service.dart';
import '../providers/provider_client.dart';
import '../providers/provider_factory.dart';

/// C.B — Clone Builder. Takes a URL, file content or plain description of
/// any app / skill / project and produces a functional equivalent as a Pixel
/// no-code skill (JSON step graph) plus a CS.B-ready flow. Clones are always
/// AI-assisted interpretations adapted to the Pixel ecosystem — never byte
/// copies of third-party assets.
class CloneService {
  final DatabaseService db;

  CloneService({required this.db});

  Future<Skill> clone({
    required String input,
    String? url,
    String? fileContent,
    String? fileName,
  }) async {
    final provider = await _pickProvider();
    if (provider == null) {
      throw StateError(
          'C.B needs at least one AI provider with an API key configured.');
    }
    final client = ProviderFactory.create(provider);

    final prompt = _buildPrompt(input: input, url: url, fileName: fileName);
    final res = await client.chat([
      const ChatMsg('system',
          'You are the Clone Engine of the Pixel AI harness. You convert an '
              'existing app/skill/tool described by the user into a Pixel no-code '
              'skill definition. Output STRICTLY one JSON object with no prose.'),
      ChatMsg('user', prompt),
    ]);

    final spec = _parseSpec(res.text);
    final now = DateTime.now();
    final skill = Skill(
      id: spec['id'],
      name: spec['name'],
      description: spec['description'],
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
      source: FeatureSource.cloned,
      safetyScore: 80,
      enabled: false,
      shortcutTarget: 'mib',
    ));
    return skill;
  }

  Future<Skill> buildFromFile({
    required String fileName,
    required String content,
  }) async {
    return clone(input: '', fileContent: content, fileName: fileName);
  }

  Future<ProviderConfig?> _pickProvider() async {
    final provs = await db.listProviders();
    for (final p in provs) {
      if (p.enabled && p.apiKey?.isNotEmpty == true) return p;
    }
    return null;
  }

  String _buildPrompt({
    required String input,
    String? url,
    String? fileContent,
    String? fileName,
  }) {
    final buf = StringBuffer();
    buf.writeln('Clone this into a Pixel skill:');
    if (input.trim().isNotEmpty) buf.writeln('DESCRIPTION:\n$input');
    if (url != null) buf.writeln('SOURCE URL: $url');
    if (fileName != null) buf.writeln('FILE: $fileName');
    if (fileContent != null) {
      buf.writeln('CONTENT (truncated to 12000 chars):\n'
          '${fileContent.length > 12000 ? fileContent.substring(0, 12000) : fileContent}');
    }
    buf.writeln('''
Generate a functional equivalent adapted to the Pixel ecosystem.

JSON SCHEMA (return ONLY this):
{
  "id": "short-kebab-name",
  "name": "Human readable name",
  "description": "one sentence what it does",
  "steps": [
    {
      "name": "step1",
      "type": "prompt" | "provider" | "condition" | "concatenate" | "extract",
      "params": {...}
    }
  ]
}

Rules:
- Steps run in order; use {step1} placeholders for earlier outputs.
- 'provider' steps MUST have params.prompt and optionally params.model.
- Never claim to replicate trademarked branding; focus on the workflow.
- Keep it to 2-6 steps.
- Pixel runs these steps fully locally; that is the user's value.
''');
    return buf.toString();
  }

  Map<String, dynamic> _parseSpec(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end < start) {
      throw StateError('Clone engine returned no valid JSON. Review the '
          'provider response in MI.B and retry.');
    }
    try {
      final spec = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      if (spec['steps'] is! List || (spec['steps'] as List).isEmpty) {
        throw StateError('Clone produced no executable steps.');
      }
      return spec;
    } catch (e) {
      throw StateError('Malformed clone output from provider: $e');
    }
  }
}