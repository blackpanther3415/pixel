import 'dart:convert';

enum GraphNodeType {
  input,
  prompt,
  provider,
  model,
  skill,
  condition,
  script,
  dataSource,
  securityPolicy,
  router,
  output,
}

class GraphNode {
  final String id;
  final GraphNodeType type;
  final String label;
  final double x;
  final double y;
  final Map<String, dynamic> config;

  const GraphNode({
    required this.id,
    required this.type,
    required this.label,
    this.x = 0,
    this.y = 0,
    this.config = const {},
  });

  GraphNode copyWith({
    String? id,
    GraphNodeType? type,
    String? label,
    double? x,
    double? y,
    Map<String, dynamic>? config,
  }) =>
      GraphNode(
        id: id ?? this.id,
        type: type ?? this.type,
        label: label ?? this.label,
        x: x ?? this.x,
        y: y ?? this.y,
        config: config ?? this.config,
      );

  Map<String, Object?> toDb() => {
        'node_id': id,
        'type': type.name,
        'label': label,
        'x': x,
        'y': y,
        'config': _encode(config),
      };

  factory GraphNode.fromDb(Map<String, Object?> m) => GraphNode(
        id: m['node_id'] as String,
        type: GraphNodeType.values.firstWhere(
            (t) => t.name == m['type'],
            orElse: () => GraphNodeType.input),
        label: (m['label'] as String?) ?? 'node',
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        config: _decode(m['config'] as String?),
      );

  static String _encode(Map<String, dynamic> c) => jsonEncode(c);
  static Map<String, dynamic> _decode(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

class GraphEdge {
  final String id;
  final String fromNode;
  final String toNode;
  final String label;

  const GraphEdge({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.label = '',
  });

  Map<String, Object?> toDb() => {
        'edge_id': id,
        'from_node': fromNode,
        'to_node': toNode,
        'label': label,
      };

  factory GraphEdge.fromDb(Map<String, Object?> m) => GraphEdge(
        id: m['edge_id'] as String,
        fromNode: m['from_node'] as String,
        toNode: m['to_node'] as String,
        label: (m['label'] as String?) ?? '',
      );
}

class GraphFlow {
  final String id;
  final String name;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  const GraphFlow({
    required this.id,
    required this.name,
    this.nodes = const [],
    this.edges = const [],
  });

  Map<String, Object?> toDb() => {
        'id': id,
        'name': name,
      };
}