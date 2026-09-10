enum SkillType { noCode, code }

enum SkillStatus { draft, active, inactive, quarantined }

class Skill {
  final String id;
  final String name;
  final String description;
  final SkillType type;
  final SkillStatus status;
  final String? code; // dart source for code plugins
  final String? graphJson; // node-edge JSON for no-code skills
  final String? version;
  final int safetyScore; // 0..100 from G.B review
  final DateTime createdAt;
  final DateTime updatedAt;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.status = SkillStatus.draft,
    this.code,
    this.graphJson,
    this.version = '0.1.0',
    this.safetyScore = 100,
    required this.createdAt,
    required this.updatedAt,
  });

  Skill copyWith({
    String? name,
    String? description,
    SkillStatus? status,
    String? code,
    String? graphJson,
    String? version,
    int? safetyScore,
  }) =>
      Skill(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type,
        status: status ?? this.status,
        code: code ?? this.code,
        graphJson: graphJson ?? this.graphJson,
        version: version ?? this.version,
        safetyScore: safetyScore ?? this.safetyScore,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type.name,
        'status': status.name,
        'code': code,
        'graph_json': graphJson,
        'version': version,
        'safety': safetyScore,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Skill.fromDb(Map<String, Object?> m) => Skill(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Untitled',
        description: (m['description'] as String?) ?? '',
        type: SkillType.values.firstWhere(
            (t) => t.name == m['type'],
            orElse: () => SkillType.noCode),
        status: SkillStatus.values.firstWhere(
            (s) => s.name == m['status'],
            orElse: () => SkillStatus.draft),
        code: m['code'] as String?,
        graphJson: m['graph_json'] as String?,
        version: (m['version'] as String?) ?? '0.1.0',
        safetyScore: (m['safety'] as int?) ?? 100,
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse((m['updated_at'] as String?) ?? '') ??
                DateTime.now(),
      );
}

class SkillRun {
  final int? id;
  final String skillId;
  final String status; // 'running' | 'pass' | 'fail' | 'blocked'
  final String? input;
  final String? output;
  final String? error;
  final int durationMs;
  final DateTime createdAt;

  const SkillRun({
    this.id,
    required this.skillId,
    required this.status,
    this.input,
    this.output,
    this.error,
    this.durationMs = 0,
    required this.createdAt,
  });

  Map<String, Object?> toDb() => {
        'skill_id': skillId,
        'status': status,
        'input': input,
        'output': output,
        'error': error,
        'duration_ms': durationMs,
        'created_at': createdAt.toIso8601String(),
      };

  factory SkillRun.fromDb(Map<String, Object?> m) => SkillRun(
        id: m['id'] as int?,
        skillId: m['skill_id'] as String,
        status: (m['status'] as String?) ?? 'running',
        input: m['input'] as String?,
        output: m['output'] as String?,
        error: m['error'] as String?,
        durationMs: (m['duration_ms'] as int?) ?? 0,
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '') ??
                DateTime.now(),
      );
}