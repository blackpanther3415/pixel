import 'dart:async';

import '../../models/security_event.dart';
import '../database/database_service.dart';
import 'security_engine.dart';

export '../../models/security_event.dart' show SecurityVerdict;

class GatewayScanned {
  final String sanitized;
  final List<SecurityEvent> events;
  final bool blocked;

  const GatewayScanned({
    required this.sanitized,
    required this.events,
    required this.blocked,
  });
}

/// G.B — the mandatory security gateway. Every inbound string (user -> model)
/// and outbound string (model -> user / model -> skill) is routed through
/// [scanInbound] / [scanOutbound] before it is allowed to proceed.
class SecurityGateway {
  final DatabaseService db;
  final SecurityEngine engine;
  SecurityLevel level = SecurityLevel.medium;

  SecurityGateway({required this.db, required this.engine});

  void loadLevel(AppSettings s) {
    level = SecurityLevel.values.firstWhere(
        (l) => l.name == s.securityLevel,
        orElse: () => SecurityLevel.medium);
  }

  /// Scan data travelling INTO an AI provider. Returns sanitized text and
  /// any raised events. If [blocked] is true the request must not be sent.
  Future<GatewayScanned> scanInbound({
    required String text,
    String? route,
    List<int>? fileBytes,
  }) async {
    final results = fileBytes != null
        ? engine.scanBytes(fileBytes, level)
        : engine.scanText(text, level);
    return _process(text, results, 'inbound', route, fileBytes);
  }

  /// Scan data travelling OUT of an AI provider (responses / generated code).
  Future<GatewayScanned> scanOutbound({
    required String text,
    String? route,
    List<int>? fileBytes,
  }) async {
    final results = fileBytes != null
        ? engine.scanBytes(fileBytes, level)
        : engine.scanText(text, level);
    return _process(text, results, 'outbound', route, fileBytes);
  }

  Future<GatewayScanned> _process(
    String original,
    List<ScanResult> results,
    String direction,
    String? route,
    List<int>? fileBytes,
  ) async {
    final hits = results.where((r) => r.hit).toList();
    var blocked = hits.isNotEmpty;
    var sanitized = original;

    final events = <SecurityEvent>[];
    for (final hit in hits) {
      final verdict = _verdictFor(hit, level);
      if (verdict != SecurityVerdict.pass) blocked = true;
      final ev = SecurityEvent(
        category: hit.category,
        verdict: verdict,
        level: level,
        confidence: hit.confidence,
        summary: hit.summary,
        detail: hit.detail,
        direction: direction,
        route: route,
        suggestion: hit.suggestion,
        createdAt: DateTime.now(),
      );
      final id = await db.insertSecurityEvent(ev);
      events.add(ev);
      if (verdict != SecurityVerdict.pass) {
        await db.insertQuarantine(
          eventId: id,
          original: original,
          sanitized: hit.category == ScanCategory.sensitiveData
              ? _redact(original)
              : null,
          source: route,
        );
      }
    }

    if (blocked) {
      sanitized = _safeFallback(sanitized, hits);
    }

    return GatewayScanned(sanitized: sanitized, events: events, blocked: blocked);
  }

  SecurityVerdict _verdictFor(ScanResult r, SecurityLevel level) {
    if (!r.hit) return SecurityVerdict.pass;
    final c = r.confidence;
    return switch (level) {
      SecurityLevel.low => c >= 0.85
          ? SecurityVerdict.block
          : SecurityVerdict.quarantine,
      SecurityLevel.medium => c >= 0.7
          ? SecurityVerdict.block
          : SecurityVerdict.quarantine,
      SecurityLevel.high => c >= 0.45
          ? SecurityVerdict.block
          : SecurityVerdict.quarantine,
      SecurityLevel.custom => c >= 0.6
          ? SecurityVerdict.block
          : SecurityVerdict.quarantine,
    };
  }

  /// Sanitize strategy: never silently drop content. Provide the original with
  /// a clear warning suffix plus the recommended safe alternative.
  String _safeFallback(String original, List<ScanResult> hits) {
    final buf = StringBuffer('⚠ BLOCKED BY G.B — content was intercepted.\n');
    buf.writeln('The blocked data was NOT sent. Detected risk(s):');
    for (final h in hits) {
      buf.writeln('  • ${h.summary}');
      if (h.suggestion != null) buf.writeln('    Safe option: ${h.suggestion}');
    }
    return buf.toString();
  }

  String _redact(String s) {
    final out = StringBuffer();
    var last = 0;
    // crude redaction of the most common secret shapes
    final re = RegExp(
        r'\b(sk-[A-Za-z0-9]{20,}|[A-Za-z0-9]{32,64}|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|(\+\d{1,3}[\s-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4})\b');
    for (final m in re.allMatches(s)) {
      out.write(s.substring(last, m.start));
      out.write('█REDACTED█');
      last = m.end;
    }
    out.write(s.substring(last));
    return out.toString();
  }
}