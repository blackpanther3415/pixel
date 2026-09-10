import 'dart:convert';

import '../../models/graph_node.dart';
import '../../models/provider.dart';
import '../database/database_service.dart';
import '../knowledge/kb_service.dart';
import '../providers/provider_client.dart';
import '../providers/provider_factory.dart';
import '../security/security_gateway.dart';
import '../skills/skill_executor.dart';

/// CS.B — runtime for the visual node graph. Executes a graph topologically
/// in real time. Any node can read/write the global "blackboard" so tabs,
/// skills and providers can share live values.
class GraphRuntime {
  final DatabaseService db;
  final SecurityGateway gateway;
  final KbService? kb;
  final SkillExecutor? skills;
  final Map<String, dynamic> blackboard = {};

  GraphRuntime({
    required this.db,
    required this.gateway,
    this.kb,
    this.skills,
  });

  /// Execute a flow. [seed] provides initial input values keyed by node-id,
  /// which is how tabs bind themselves into a graph ("a node IS a binding").
  Future<Map<String, dynamic>> execute(
    GraphFlow flow, {
    Map<String, dynamic> seed = const {},
  }) async {
    blackboard.addAll(seed);
    final results = <String, dynamic>{};
    final edgesByFrom = <String, List<GraphEdge>>{};
    for (final e in flow.edges) {
      edgesByFrom.putIfAbsent(e.fromNode, () => []).add(e);
    }

    final order = _topoOrder(flow);
    for (final nodeId in order) {
      final node = flow.nodes.where((n) => n.id == nodeId).firstOrNull;
      if (node == null) continue;
      final input = _inputsFor(node.id, flow.edges, results, blackboard);
      try {
        results[node.id] = await _runNode(node, input);
        blackboard[node.label] = results[node.id];
      } catch (e) {
        results[node.id] = {'__error__': '$e'};
      }
    }
    return results;
  }

  List<String> _topoOrder(GraphFlow flow) {
    final indegree = <String, int>{for (final n in flow.nodes) n.id: 0};
    final edgesByFrom = <String, List<GraphEdge>>{};
    for (final e in flow.edges) {
      edgesByFrom.putIfAbsent(e.fromNode, () => []).add(e);
      indegree[e.toNode] = (indegree[e.toNode] ?? 0) + 1;
    }
    final queue = <String>[
      for (final n in flow.nodes)
        if (indegree[n.id] == 0) n.id,
    ];
    final order = <String>[];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      order.add(id);
      for (final e in edgesByFrom[id] ?? <GraphEdge>[]) {
        final v = (indegree[e.toNode] ?? 1) - 1;
        indegree[e.toNode] = v;
        if (v <= 0) {
          queue.insert(0, e.toNode);
        }
      }
    }
    return order;
  }

  Map<String, dynamic> _inputsFor(
    String nodeId,
    List<GraphEdge> edges,
    Map<String, dynamic> results,
    Map<String, dynamic> board,
  ) {
    final incoming = edges.where((e) => e.toNode == nodeId).toList();
    if (incoming.isEmpty) return {...board};
    final inputs = <String, dynamic>{};
    for (final e in incoming) {
      inputs[e.label.isEmpty ? e.fromNode : e.label] =
          results[e.fromNode] ?? board[e.fromNode];
    }
    return inputs;
  }

  Future<dynamic> _runNode(GraphNode node, Map<String, dynamic> input) async {
    String asText(dynamic v) {
      if (v is String) return v;
      if (v is Map || v is List) return jsonEncode(v);
      return '$v';
    }

    switch (node.type) {
      case GraphNodeType.input:
        return input[node.id] ??
            input['input'] ??
            input[node.label] ??
            input.values.firstOrNull ??
            '';

      case GraphNodeType.prompt:
        final template = (node.config['template'] as String?) ?? '';
        var out = template;
        input.forEach((k, v) {
          out = out.replaceAll('{$k}', asText(v));
        });
        return out;

      case GraphNodeType.provider:
        final prompt = asText(input.values.firstOrNull ?? '');
        if (prompt.trim().isEmpty) return '';

        final scanned =
            await gateway.scanInbound(text: prompt, route: 'CS.B:${node.id}');
        if (scanned.blocked) throw StateError('G.B blocked: ${scanned.sanitized}');

        ProviderConfig? conf;
        final providers = await db.listProviders();
        for (final p in providers) {
          if (p.id == node.config['provider_id']) conf = p;
        }
        if (conf == null) {
          for (final p in providers) {
            if (p.enabled && p.apiKey?.isNotEmpty == true) {
              conf = p;
              break;
            }
          }
        }
        if (conf == null) throw StateError('No provider configured');

        final client = ProviderFactory.create(conf);
        final model =
            (node.config['model'] as String?) ?? conf.models.lastOrNull?.id ?? '';
        final res = await client.chat(
          [ChatMsg('user', scanned.sanitized)],
          model: model.isEmpty ? null : model,
          temperature:
              ((node.config['temperature'] as num?)?.toDouble() ?? 0.3),
        );
        final out = await gateway.scanOutbound(
            text: res.text, route: 'CS.B:${node.id}');
        if (out.blocked) throw StateError('G.B blocked output');
        return out.sanitized;

      case GraphNodeType.condition:
        final value = asText(input.values.firstOrNull ?? '');
        final cond = (node.config['expr'] as String?) ?? '';
        final eval =
            cond.isEmpty ? value.isNotEmpty : _evalCondition(cond, value);
        blackboard['condition.${node.id}'] = eval;
        return value;

      case GraphNodeType.router:
        final value = asText(input.values.firstOrNull ?? '');
        final key = (node.config['key'] as String?) ?? 'mode';
        blackboard['route.$key'] = value;
        return value;

      case GraphNodeType.dataSource:
        final kbs = kb;
        if (kbs == null) return '';
        final query = asText(input.values.firstOrNull ?? '');
        final k = (node.config['kb_length'] as num?)?.toInt() ?? 6;
        final docs = await kbs.search(query, limit: k);
        return docs.map((c) => c.text).join('\n');

      case GraphNodeType.securityPolicy:
        final value = asText(input.values.firstOrNull ?? '');
        final scanned =
            await gateway.scanInbound(text: value, route: 'CS.B:security');
        if (scanned.blocked) throw StateError('G.B policy node blocked payload');
        return value;

      case GraphNodeType.script:
        final code = (node.config['code'] as String?) ?? '';
        if (code.trim().isEmpty) return '';
        final args = jsonEncode(input);
        return '# script code $code\nargs=$args';

      case GraphNodeType.skill:
        final skillId = (node.config['skill_id'] as String?) ?? '';
        if (skillId.isNotEmpty && skills != null) {
          final r = await skills!.runSkill(skillId,
              input: jsonEncode(input.isEmpty ? blackboard : input));
          return r.passed ? r.output : r.error ?? '';
        }
        return '';

      case GraphNodeType.model:
        return asText(input.values.firstOrNull ?? '');

      case GraphNodeType.output:
        final v = input.values.firstOrNull ?? '';
        blackboard['output'] = v;
        return v;
    }
  }

  bool _evalCondition(String expr, String value) {
    final e = expr.trim();
    if (e.startsWith('length>')) {
      final n = int.tryParse(e.substring(7).trim()) ?? 0;
      return value.length > n;
    }
    if (e.startsWith('contains:')) {
      return value.contains(e.substring(9).trim());
    }
    if (e.startsWith('regex:')) {
      return RegExp(e.substring(6).trim()).hasMatch(value);
    }
    if (e == 'nonempty') return value.trim().isNotEmpty;
    return value.isNotEmpty;
  }
}