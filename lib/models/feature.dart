import 'package:uuid/uuid.dart';

enum FeatureSource { builtin, built, cloned, trained }

class Feature {
  final String id;
  final String name;
  final String description;
  final FeatureSource source;
  final bool enabled;
  final bool favorite;
  final int safetyScore; // 0..100 from G.B
  final int usageCount;
  final String? dependencyIds; // comma separated feature ids
  final String? shortcutTarget; // 'mlb' | 'csb' | 'lb' | ...
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const Feature({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    this.enabled = true,
    this.favorite = false,
    this.safetyScore = 100,
    this.usageCount = 0,
    this.dependencyIds,
    this.shortcutTarget,
    required this.createdAt,
    this.lastUsedAt,
  });

  const Feature._({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.enabled,
    required this.favorite,
    required this.safetyScore,
    required this.usageCount,
    this.dependencyIds,
    this.shortcutTarget,
    required this.createdAt,
    this.lastUsedAt,
  });

  static const _uuid = Uuid();

  factory Feature.create({
    required String name,
    required String description,
    required FeatureSource source,
    int safetyScore = 100,
    bool enabled = false,
    String? dependencyIds,
    String? shortcutTarget,
  }) =>
      Feature._(
        id: _uuid.v4(),
        name: name,
        description: description,
        source: source,
        enabled: enabled,
        favorite: false,
        safetyScore: safetyScore,
        usageCount: 0,
        dependencyIds: dependencyIds,
        shortcutTarget: shortcutTarget,
        createdAt: DateTime.now(),
      );

  Feature copyWith({
    bool? enabled,
    bool? favorite,
    int? usageCount,
    DateTime? lastUsedAt,
  }) =>
      Feature._(
        id: id,
        name: name,
        description: description,
        source: source,
        enabled: enabled ?? this.enabled,
        favorite: favorite ?? this.favorite,
        safetyScore: safetyScore,
        usageCount: usageCount ?? this.usageCount,
        dependencyIds: dependencyIds,
        shortcutTarget: shortcutTarget,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'name': name,
        'description': description,
        'source': source.name,
        'enabled': enabled ? 1 : 0,
        'favorite': favorite ? 1 : 0,
        'safety': safetyScore,
        'usage': usageCount,
        'dependencies': dependencyIds,
        'shortcut': shortcutTarget,
        'created_at': createdAt.toIso8601String(),
        'last_used': lastUsedAt?.toIso8601String(),
      };

  factory Feature.fromDb(Map<String, Object?> m) => Feature._(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Feature',
        description: (m['description'] as String?) ?? '',
        source: FeatureSource.values.firstWhere(
            (s) => s.name == m['source'],
            orElse: () => FeatureSource.builtin),
        enabled: (m['enabled'] as int? ?? 1) == 1,
        favorite: (m['favorite'] as int? ?? 0) == 1,
        safetyScore: (m['safety'] as int?) ?? 100,
        usageCount: (m['usage'] as int?) ?? 0,
        dependencyIds: m['dependencies'] as String?,
        shortcutTarget: m['shortcut'] as String?,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.now(),
        lastUsedAt: m['last_used'] == null
            ? null
            : DateTime.tryParse(m['last_used'] as String),
      );
}