import 'dart:async';
import 'dart:convert';

import '../../models/provider.dart';
import '../../models/skill.dart';
import '../database/database_service.dart';
import '../providers/provider_client.dart';
import '../providers/provider_factory.dart';
import '../security/security_gateway.dart';

/// A single step inside a no-code skill graph. Steps run in dataflow order:
/// the `inputs` map names fields gathered from earlier step outputs.
class SkillStep {
  final String name;
  final String type; // 'prompt' | 'provider' | 'condition' | 'concatenate' | 'extract'
  final Map<String, dynamic> params;

  const SkillStep({required this.name, required this.type, this.params = const {}});

  factory SkillStep.fromJson(Map<String, dynamic> j) => SkillStep(
        name: (j['name'] as String?) ?? 'step',
        type: (j['type'] as String?) ?? 'prompt',
        params: (j['params'] as Map<String, dynamic>?) ?? const {},
      );
  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'params': params};
}

class SkillSpec {
  final String id;
  final String name;
  final String description;
  final List<SkillStep> steps;

  const SkillSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
  });

  factory SkillSpec.fromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return SkillSpec(
      id: (m['id'] as String?) ?? 'skill',
      name: (m['name'] as String?) ?? 'Skill',
      description: (m['description'] as String?) ?? '',
      steps: [
        for (final s in (m['steps'] as List? ?? []))
          SkillStep.fromJson(s as Map<String, dynamic>)
      ],
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'description': description,
        'steps': [for (final s in steps) s.toJson()],
      });
}

class SkillResult {
  final String output;
  final bool passed;
  final String? error;
  const SkillResult({required this.output, required this.passed, this.error});
}

/// Executes no-code skills (JSON graph of steps) with G.B gating on every
/// provider call. Step outputs are interpolated into later prompt steps via
/// {stepName} placeholders.
class SkillExecutor {
  final DatabaseService db;
  final SecurityGateway gateway;

  SkillExecutor({
    required this.db,
    required this.gateway,
  });

  Future<SkillResult> runSkill(String skillId, {String? input}) async {
    final skills = await db.listSkills();
    final skill = skills.where((s) => s.id == skillId).firstOrNull;
    if (skill == null) return const SkillResult(output: '', passed: false, error: 'unknown skill');
    return runSpec(skill, input: input);
  }

  Future<SkillResult> runSpec(Skill skill, {String? input}) async {
    final sw = Stopwatch()..start();
    final outputs = <String, String>{'input': input ?? '{}'};
    final runs = <String>[];
    try {
      final spec = SkillSpec.fromJson(skill.graphJson!);
      for (final step in spec.steps) {
        final out = await _runStep(step, outputs, spec);
        outputs[step.name] = out;
        runs.add('${step.name}=${out.length}ch');
      }
      sw.stop();
      if (sw.elapsedMilliseconds > 0) {}
      return SkillResult(
        output: outputs.values.last,
        passed: true,
      );
    } catch (e) {
      return SkillResult(output: '', passed: false, error: '$e');
    }
  }

  Future<String> _runStep(
      SkillStep step, Map<String, String> outputs, SkillSpec spec) async {
    String interpolate(String t) {
      var out = t;
      for (final e in outputs.entries) {
        out = out.replaceAll('{${e.key}}', e.value);
      }
      return out;
    }

    switch (step.type) {
      case 'concatenate':
        final parts = (step.params['parts'] as List? ?? [])
            .map((p) => interpolate(p.toString()))
            .join((step.params['joiner'] as String?) ?? '\n');
        return parts;

      case 'condition':
        final value = interpolate((step.params['value'] as String?) ?? '');
        final isTrue = value.isNotEmpty;
        outputs['condition_result'] = isTrue.toString();
        return value;

      case 'extract':
        final value = interpolate((step.params['source'] as String?) ?? '');
        final pattern = RegExp((step.params['pattern'] as String?) ?? '');
        final m = pattern.firstMatch(value);
        return m?.group(1) ?? '';

      case 'prompt':
      case 'provider':
        final prompt = interpolate((step.params['prompt'] as String?) ?? '');

        ProviderConfig? providerConf;
        if (step.params['provider_id'] != null) {
          final providers = await db.listProviders();
          for (final p in providers) {
            if (p.id == step.params['provider_id']) providerConf = p;
          }
          if (providerConf == null) {
            throw StateError('provider ${step.params['provider_id']} not found');
          }
        } else {
          final providers = await db.listProviders();
          for (final p in providers) {
            if (p.enabled && p.apiKey?.isNotEmpty == true) {
              providerConf = p;
              break;
            }
          }
        }
        if (providerConf == null) throw StateError('No provider configured');

        // G.B inbound gate
        final scanned =
            await gateway.scanInbound(text: prompt, route: 'skill:$spec.id');
        if (scanned.blocked) {
          throw StateError('G.B blocked skill input: ${scanned.sanitized}');
        }

        final client = ProviderFactory.create(providerConf);
        final model = (step.params['model'] as String?) ??
            providerConf.models.lastOrNull?.id ??
            '';
        final temperature = ((step.params['temperature'] as num?)?.toDouble() ?? 0.3);
        final result = await client.chat(
          [ChatMsg('user', scanned.sanitized)],
          model: model.isEmpty ? null : model,
          temperature: temperature,
        );

        // G.B outbound gate
        final outScanned =
            await gateway.scanOutbound(text: result.text, route: 'skill:$spec.id');
        if (outScanned.blocked) {
          throw StateError('G.B blocked skill output');
        }
        return outScanned.sanitized;

      default:
        throw StateError('unknown step type ${step.type}');
    }
  }
}