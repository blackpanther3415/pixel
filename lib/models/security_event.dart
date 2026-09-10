import 'package:intl/intl.dart';

enum SecurityLevel { low, medium, high, custom }

enum SecurityVerdict { pass, block, quarantine }

enum ScanCategory {
  promptInjection,
  sensitiveData,
  harmfulContent,
  maliciousCode,
  fileMalware,
}

class SecurityEvent {
  final int? id;
  final ScanCategory category;
  final SecurityVerdict verdict;
  final SecurityLevel level;
  final double confidence;
  final String summary;
  final String detail;
  final String direction; // 'inbound' | 'outbound'
  final String? route; // which tab / provider was involved
  final String? suggestion; // safe alternative suggestion
  final bool resolved;
  final DateTime createdAt;

  const SecurityEvent({
    this.id,
    required this.category,
    required this.verdict,
    required this.level,
    required this.confidence,
    required this.summary,
    required this.detail,
    required this.direction,
    this.route,
    this.suggestion,
    this.resolved = false,
    required this.createdAt,
  });

  SecurityEvent copyWith({bool? resolved}) => SecurityEvent(
        id: id,
        category: category,
        verdict: verdict,
        level: level,
        confidence: confidence,
        summary: summary,
        detail: detail,
        direction: direction,
        route: route,
        suggestion: suggestion,
        resolved: resolved ?? this.resolved,
        createdAt: createdAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'category': category.name,
        'verdict': verdict.name,
        'level': level.name,
        'confidence': confidence,
        'summary': summary,
        'detail': detail,
        'direction': direction,
        'route': route,
        'suggestion': suggestion,
        'resolved': resolved ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory SecurityEvent.fromDb(Map<String, Object?> m) => SecurityEvent(
        id: m['id'] as int?,
        category: ScanCategory.values.firstWhere((c) =>
            c.name == m['category'],
            orElse: () => ScanCategory.promptInjection),
        verdict: SecurityVerdict.values.firstWhere(
            (v) => v.name == m['verdict'],
            orElse: () => SecurityVerdict.pass),
        level: SecurityLevel.values.firstWhere(
            (l) => l.name == m['level'],
            orElse: () => SecurityLevel.medium),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        summary: (m['summary'] as String?) ?? '',
        detail: (m['detail'] as String?) ?? '',
        direction: (m['direction'] as String?) ?? 'inbound',
        route: m['route'] as String?,
        suggestion: m['suggestion'] as String?,
        resolved: (m['resolved'] as int? ?? 0) == 1,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.now(),
      );

  String get timeLabel => DateFormat('MMM d H:mm:ss').format(createdAt);
}