import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/graph_node.dart';
import '../../widgets/common.dart';

/// CS.B — Structure Builder. A visual node canvas that customizes the whole
/// app in real time, n8n-style. Every node is draggable and connected; the
/// graph executes live when you press Run.
class StructureTab extends StatefulWidget {
  final AppState state;
  const StructureTab({super.key, required this.state});

  @override
  State<StructureTab> createState() => _StructureTabState();
}

class _StructureTabState extends State<StructureTab> {
  static const _uuid = Uuid();
  List<GraphNode> _nodes = [];
  List<GraphEdge> _edges = [];
  String? _selectedNodeId;
  Offset? _dragFrom;
  bool _running = false;
  String? _result;
  final String _flowId = 'default';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.state.services.db;
    final nodes = await db.graphNodes(_flowId);
    final edges = await db.graphEdges(_flowId);
    setState(() {
      _nodes = nodes;
      _edges = edges;
    });
    if (nodes.isEmpty) _seedDemo();
  }

  void _seedDemo() {
    setState(() {
      _nodes = [
        GraphNode(
            id: _uuid.v4(), type: GraphNodeType.input, label: 'Your question', x: 40, y: 60,
            config: const {}),
        GraphNode(
            id: _uuid.v4(), type: GraphNodeType.prompt, label: 'Prompt', x: 280, y: 60,
            config: const {
              'template': 'You are Pixel. Answer: {Your question}'
            }),
        GraphNode(
            id: _uuid.v4(), type: GraphNodeType.provider, label: 'Model', x: 520, y: 60,
            config: const {'temperature': 0.4}),
        GraphNode(
            id: _uuid.v4(), type: GraphNodeType.securityPolicy, label: 'G.B', x: 520, y: 280,
            config: const {'level': 'medium'}),
        GraphNode(
            id: _uuid.v4(), type: GraphNodeType.output, label: 'Result', x: 800, y: 60,
            config: const {}),
      ];
      _edges = [
        GraphEdge(id: _uuid.v4(), fromNode: _nodes[0].id, toNode: _nodes[1].id, label: 'text'),
        GraphEdge(id: _uuid.v4(), fromNode: _nodes[1].id, toNode: _nodes[2].id, label: 'prompt'),
        GraphEdge(id: _uuid.v4(), fromNode: _nodes[2].id, toNode: _nodes[3].id, label: 'out'),
        GraphEdge(id: _uuid.v4(), fromNode: _nodes[3].id, toNode: _nodes[4].id, label: 'clean'),
      ];
    });
    _save();
  }

  Future<void> _save() async {
    final db = widget.state.services.db;
    await db.saveGraphFlow(_flowId, 'Default flow', _nodes, _edges);
    await widget.state.refresh();
  }

  void _addNode(GraphNodeType type) {
    final id = _uuid.v4();
    setState(() {
      _nodes = [
        ..._nodes,
        GraphNode(
          id: id,
          type: type,
          label: _labelFor(type),
          x: 80 + math.Random().nextInt(60).toDouble(),
          y: 200 + math.Random().nextInt(120).toDouble(),
          config: const {},
        ),
      ];
    });
    _save();
  }

  String _labelFor(GraphNodeType t) => switch (t) {
        GraphNodeType.input => 'Input',
        GraphNodeType.prompt => 'Prompt',
        GraphNodeType.provider => 'LLM call',
        GraphNodeType.model => 'Model',
        GraphNodeType.skill => 'Skill',
        GraphNodeType.condition => 'If…',
        GraphNodeType.script => 'Script',
        GraphNodeType.dataSource => 'Knowledge',
        GraphNodeType.securityPolicy => 'G.B policy',
        GraphNodeType.router => 'Router',
        GraphNodeType.output => 'Output',
      };

  void _connect(String from, String to) {
    if (from == to) return;
    final exists =
        _edges.any((e) => e.fromNode == from && e.toNode == to);
    if (exists) return;
    setState(() {
      _edges = [..._edges, GraphEdge(id: _uuid.v4(), fromNode: from, toNode: to, label: '')];
    });
    _save();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final flow = GraphFlow(id: _flowId, name: 'Default flow', nodes: _nodes, edges: _edges);
    final runtime = widget.state.services.graph;
    final seed = <String, dynamic>{};
    for (final n in _nodes.where((n) => n.type == GraphNodeType.input)) {
      seed[n.id] = _inputValues[n.id] ?? 'Explain Pixel in two lines.';
    }
    final results = await runtime.execute(flow, seed: seed);
    setState(() {
      _result = results.values
          .where((v) => v is String && v.toString().isNotEmpty)
          .map((v) => v.toString())
          .lastOrNull ??
          'Flow completed with no string output.';
      _running = false;
    });
  }

  final Map<String, String> _inputValues = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              const Icon(Icons.account_tree, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                    'CS.B · real-time node graph — customize Pixel by wiring it',
                    style: TextStyle(color: AppColors.textMid, fontSize: 13)),
              ),
              PixelButton(
                label: 'Run',
                icon: Icons.play_arrow,
                busy: _running,
                onPressed: _run,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D1220),
                    ),
                    child: CustomPaint(
                      painter: _GridPainter(),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                  ),
                  ..._buildEdges(),
                  ..._buildNodes(constraints),
                  if (_selectedNodeId != null)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: _NodeToolbar(
                        node: _nodes
                            .where((n) => n.id == _selectedNodeId)
                            .firstOrNull,
                        onConfigure: _configure,
                        onDelete: _deleteNode,
                        onDuplicate: _duplicateNode,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        _NodePalette(onAdd: _addNode),
        if (_result != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text('RESULT: $_result',
                style: const TextStyle(color: AppColors.good, fontSize: 13)),
          ),
      ],
    );
  }

  List<Widget> _buildNodes(BoxConstraints c) {
    final result = _inputValues;
    return [
      for (final n in _nodes)
        Positioned(
          left: n.x,
          top: n.y,
          child: GestureDetector(
            onTap: () => setState(() => _selectedNodeId = n.id),
            onPanUpdate: (d) {
              _dragFrom ??= Offset(n.x, n.y);
              setState(() {
                final start = _dragFrom!;
                _nodes = _nodes.map((x) {
                  if (x.id == n.id) {
                    return x.copyWith(
                        x: (start.dx + d.delta.dx).clamp(0.0, 2000.0),
                        y: (start.dy + d.delta.dy).clamp(0.0, 2000.0));
                  }
                  return x;
                }).toList();
              });
            },
            onPanEnd: (_) {
              _dragFrom = null;
              _save();
            },
            child: _NodeCard(
              node: n,
              selected: n.id == _selectedNodeId,
              inputValue: result[n.id],
              onEdit: () => _configure(n),
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildEdges() {
    return [
      for (final e in _edges)
        _EdgePainter(
          from: _nodePos(e.fromNode),
          to: _nodePos(e.toNode),
          label: e.label,
        )
    ];
  }

  Offset? _nodePos(String id) {
    final n = _nodes.where((n) => n.id == id).firstOrNull;
    if (n == null) return null;
    return Offset(n.x + 90, n.y + 30);
  }

  void _deleteNode(String id) {
    setState(() {
      _nodes = _nodes.where((n) => n.id != id).toList();
      _edges = _edges
          .where((e) => e.fromNode != id && e.toNode != id)
          .toList();
      _selectedNodeId = null;
    });
    _save();
  }

  void _duplicateNode(String id) {
    final n = _nodes.where((n) => n.id == id).firstOrNull;
    if (n == null) return;
    setState(() {
      _nodes = [
        ..._nodes,
        n.copyWith(id: _uuid.v4(), x: n.x + 30, y: n.y + 30),
      ];
    });
    _save();
  }

  Future<void> _configure(GraphNode? n) async {
    if (n == null) return;
    if (n.type == GraphNodeType.input) {
      final text = await _promptForInput();
      if (text != null) {
        setState(() => _inputValues[n.id] = text);
      }
      return;
    }
    final configJson = await showDialogText(
        context,
        'Configure ${n.label}',
        'Enter JSON config for this node:',
        n.config.isEmpty ? '{}' : n.config.toString());
    if (configJson != null) {
      try {
        setState(() {
          _nodes = _nodes.map((x) {
            if (x.id == n.id) {
              return x.copyWith(config: _tryParseJson(configJson));
            }
            return x;
          }).toList();
        });
        _save();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Invalid JSON: $e')));
        }
      }
    }
    if (!mounted) return;
    final linkTarget = await _promptLink();
    if (linkTarget != null) {
      _connect(n.id, linkTarget);
    }
  }

  Future<String?> _promptForInput() async {
    final controller = TextEditingController(text: _inputValues.values.firstOrNull ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('Input value'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, controller.text),
              child: const Text('Set')),
        ],
      ),
    );
    return result == '' ? null : result;
  }

  Future<String?> _promptLink() async {
    final other = _nodes.where((n) => n.id != _selectedNodeId).toList();
    if (other.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('Connect to'),
        children: [
          for (final n in other)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, n.id),
              child: Text(n.label),
            ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _tryParseJson(String s) {
    // simple key: value parser fallback
    final out = <String, dynamic>{};
    for (final part in s.split(RegExp(r'[,{]'))) {
      final kv = part.split(':');
      if (kv.length == 2) {
        var k = kv[0].trim().replaceAll('"', '').trim();
        var v = kv[1].trim().replaceAll('"', '').trim();
        out[k] = num.tryParse(v) ?? v;
      }
    }
    return out.isEmpty ? {'raw': s} : out;
  }
}

Future<String?> showDialogText(
    BuildContext context, String title, String hint, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Save')),
      ],
    ),
  );
}

class _NodeToolbar extends StatelessWidget {
  final GraphNode? node;
  final Future<void> Function(GraphNode) onConfigure;
  final void Function(String) onDelete;
  final void Function(String) onDuplicate;
  const _NodeToolbar({
    required this.node,
    required this.onConfigure,
    required this.onDelete,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final n = node;
    if (n == null) return const SizedBox.shrink();
    return Card(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(n.label,
              style: const TextStyle(
                  color: AppColors.textHigh, fontSize: 12, fontWeight: FontWeight.w600)),
          IconButton(
              icon: const Icon(Icons.settings, size: 16),
              tooltip: 'Configure',
              onPressed: () => onConfigure(n)),
          IconButton(
              icon: const Icon(Icons.call_split, size: 16),
              tooltip: 'Connect',
              onPressed: () => onConfigure(n)),
          IconButton(
              icon: const Icon(Icons.content_copy, size: 16),
              tooltip: 'Duplicate',
              onPressed: () => onDuplicate(n.id)),
          IconButton(
              icon: const Icon(Icons.delete, size: 16, color: AppColors.bad),
              tooltip: 'Delete',
              onPressed: () => onDelete(n.id)),
        ],
      ),
    );
  }
}

class _NodePalette extends StatelessWidget {
  final void Function(GraphNodeType) onAdd;
  const _NodePalette({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    const types = [
      (GraphNodeType.input, 'Input'),
      (GraphNodeType.prompt, 'Prompt'),
      (GraphNodeType.provider, 'LLM'),
      (GraphNodeType.securityPolicy, 'G.B'),
      (GraphNodeType.dataSource, 'KB'),
      (GraphNodeType.condition, 'If'),
      (GraphNodeType.output, 'Out'),
    ];
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (t, label) in types)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(label),
                  avatar: Icon(_iconFor(t), size: 14),
                  onPressed: () => onAdd(t),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(GraphNodeType t) => switch (t) {
      GraphNodeType.input => Icons.input,
      GraphNodeType.prompt => Icons.edit_note,
      GraphNodeType.provider => Icons.bolt,
      GraphNodeType.securityPolicy => Icons.shield,
      GraphNodeType.dataSource => Icons.psychology,
      GraphNodeType.condition => Icons.alt_route,
      GraphNodeType.output => Icons.output,
      _ => Icons.circle,
    };

class _NodeCard extends StatelessWidget {
  final GraphNode node;
  final bool selected;
  final String? inputValue;
  final VoidCallback onEdit;
  const _NodeCard(
      {required this.node,
      required this.selected,
      this.inputValue,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final color = switch (node.type) {
      GraphNodeType.input => AppColors.accent,
      GraphNodeType.provider => AppColors.primaryLight,
      GraphNodeType.securityPolicy => AppColors.warn,
      GraphNodeType.output => AppColors.good,
      GraphNodeType.dataSource => AppColors.primary,
      _ => AppColors.textMid,
    };
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected ? AppColors.primaryLight : AppColors.border, width: selected ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_iconFor(node.type), size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textHigh,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
              InkWell(
                onTap: onEdit,
                child: const Icon(Icons.edit, size: 13, color: AppColors.textLow),
              ),
            ],
          ),
          if (inputValue != null && node.type == GraphNodeType.input) ...[
            const SizedBox(height: 6),
            Text(inputValue!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMid, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EdgePainter extends StatelessWidget {
  final Offset? from;
  final Offset? to;
  final String label;
  const _EdgePainter({this.from, this.to, required this.label});

  @override
  Widget build(BuildContext context) {
    if (from == null || to == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _EdgePathPainter(from!, to!),
          size: const Size(4000, 4000),
        ),
      ),
    );
  }
}

class _EdgePathPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  _EdgePathPainter(this.from, this.to);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
          from.dx + 60, from.dy, to.dx - 60, to.dy, to.dx, to.dy);
    canvas.drawPath(path, paint);
    canvas.drawCircle(to, 4, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}