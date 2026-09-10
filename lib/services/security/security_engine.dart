import 'dart:convert';
import 'dart:math';

import '../../models/security_event.dart';

class ScanResult {
  final ScanCategory category;
  final bool hit;
  final double confidence;
  final String summary;
  final String detail;
  final String? suggestion;

  const ScanResult({
    required this.category,
    this.hit = false,
    this.confidence = 0,
    this.summary = '',
    this.detail = '',
    this.suggestion,
  });
}

/// Pure-Dart heuristic security engine. Every detector is local — nothing
/// leaves the device. Malware detection uses magic-byte signatures + embedded
/// payload heuristics; prompt injection uses structural patterns.
class SecurityEngine {
  // ---- Prompt injection patterns (case-insensitive) ----
  static final RegExp _injectionPatterns = RegExp(
    r'(ignore (all )?(previous|above|prior|earlier) (instructions|prompts|messages|context))'
    r'|(you are now (jailbroken|unrestricted|in dan mode|without.*rules))'
    r'|(disregard (the )?(above|previous|all|system).*(instructions|rules))'
    r'|(forget (everything|all)|new instructions|override your instructions)'
    r'|(act as (though )?you (are|have)|pretend you are)'
    r'|(system prompt|developer prompt)'
    r'|(reveal (your|the) (system|internal|hidden) (prompt|instructions|rules))'
    r'|(<|\[)?(system|assistant|developer)(>|\])'
    r'|(print (the )?(above|system|instructions))',
    caseSensitive: false,
  );

  static final RegExp _secretPattern = RegExp(
    r'\b(sk-[A-Za-z0-9]{20,}|sk-proj-[A-Za-z0-9_\-]{20,})'
    r'|[A-Za-z0-9]{32,64}(?![A-Za-z0-9])' // plausible API tokens
    r'|AKIA[0-9A-Z]{16}' // AWS
    r'|gh[pousr]_[A-Za-z0-9]{20,}'
    r'|xox[baprs]-[A-Za-z0-9-]{10,}'
    r'|\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.\S*', // JWT
  );

  static final RegExp _piiPattern = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b' // email
    r'|(\+\d{1,3}[\s-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b' // phone
    r'|\b(4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b' // card
    r'|\b\d{3}-\d{2}-\\d{4}\b', // SSN
    caseSensitive: false,
  );

  static const List<String> _harmfulTerms = [
    'how to build a bomb', 'make molotov', 'synthesize fentanyl',
    'credit card fraud', 'create ransomware', 'steal someone identity',
    'child exploitation', 'sell illegal drugs', 'bomb making guide',
  ];

  static final RegExp _codePattern = RegExp(
    r'<(script|iframe|object|embed|form)[\s>]'
    r'|eval\s*\('
    r'|atob\s*\('
    r'|base64_decode\s*\('
    r'|exec\s*\(|system\s*\(|popen\s*\('
    r'|Runtime\.getRuntime\(\).*exec'
    r'|process\.exec|child_process'
    r'|SqlCommand\(.*DROP TABLE'
    r'|os\.remove\(|import shutil.*rmtree'
    r'|subprocess\.(Popen|call|run)\s*\('
    r'|--exec|--eval\b|curl.*\|\s*sh',
    caseSensitive: false,
  );

  /// Magic-byte signatures for known dangerous / surprising binary types.
  static const Map<String, List<int>> _magic = {
    'ELF': [0x7F, 0x45, 0x4C, 0x46],
    'PE': [0x4D, 0x5A],
    'MachO': [0xCF, 0xFA, 0xED, 0xFE],
    'ZIP/PK': [0x50, 0x4B], // can contain macros / malware
  };

  const SecurityEngine();

  /// Scan text through all text detectors. `level` controls strictness.
  List<ScanResult> scanText(String text, SecurityLevel level) {
    final results = <ScanResult>[];
    if (text.trim().isEmpty) return results;

    results.add(_scanInjection(text));
    results.add(_scanSensitive(text));
    results.add(_scanHarmful(text));
    results.add(_scanCode(text));
    return results;
  }

  /// Scan a byte buffer (uploads/downloads) for malware signatures.
  List<ScanResult> scanBytes(List<int> bytes, SecurityLevel level) {
    final results = <ScanResult>[];
    if (bytes.length < 8) return results;

    // Decode embedded textual payloads (e.g. macrodoc) with latin1 fallback.
    String? text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      text = latin1.decode(bytes, allowInvalid: true);
    }
    results.addAll(scanText(text, level));

    final header = bytes.take(4).toList();
    String? matched;
    for (final e in _magic.entries) {
      if (_startsWith(header, e.value)) {
        matched = e.key;
        break;
      }
    }
    if (matched != null) {
      results.add(ScanResult(
        category: ScanCategory.fileMalware,
        hit: true,
        confidence: _levelThreshold(level) > 0.2 ? 0.55 : 0.95,
        summary: 'Unusual binary container detected ($matched)',
        detail: 'File begins with a $matched signature. In high security '
            'levels active binaries and archives are quarantined.',
        suggestion: 'Open the extracted text instead of executing the file.',
      ));
    }
    return results;
  }

  ScanResult _scanInjection(String text) {
    var score = 0.0;
    final matches = _injectionPatterns.allMatches(text).toList();
    score += min(1.0, matches.length * 0.33);
    // Deliberately hidden instruction blocks are suspicious.
    if (text.toLowerCase().contains('ignore') &&
        text.toLowerCase().contains('instruction')) {
      score = max(score, 0.7);
    }
    final hit = score > 0;
    return ScanResult(
      category: ScanCategory.promptInjection,
      hit: _confidentEnough(hit, score, _levelOf(text)),
      confidence: score,
      summary: hit ? 'Possible prompt injection detected' : '',
      detail: hit
          ? 'Pattern matched: ${matches.isEmpty ? "instruction override" : matches.first.group(0)!.trim()}'
          : '',
      suggestion: 'Sanitize the text, strip the directive, and ask the model '
          'to answer only the legitimate part.',
    );
  }

  ScanResult _scanSensitive(String text) {
    final secret = _secretPattern.allMatches(text).toList();
    final pii = _piiPattern.allMatches(text).toList();
    final hit = secret.isNotEmpty || pii.isNotEmpty;
    return ScanResult(
      category: ScanCategory.sensitiveData,
      hit: hit,
      confidence: min(1.0, (secret.length * 0.8) + (pii.length * 0.4)),
      summary: hit ? 'Sensitive data detected' : '',
      detail: hit
          ? '${secret.length} secret(s) and ${pii.length} PII item(s). '
              'Redact before transmitting.'
          : '',
      suggestion: 'Pixel can redact the sensitive fields automatically when '
          'quarantined.',
    );
  }

  ScanResult _scanHarmful(String text) {
    final lower = text.toLowerCase();
    final hits = _harmfulTerms.where(lower.contains).toList();
    return ScanResult(
      category: ScanCategory.harmfulContent,
      hit: hits.isNotEmpty,
      confidence: hits.isEmpty ? 0 : min(1.0, 0.5 + hits.length * 0.15),
      summary: hits.isNotEmpty ? 'Potentially harmful request content' : '',
      detail: hits.isNotEmpty
          ? 'Matched harmful phrase(s): ${hits.join(', ')}'
          : '',
      suggestion: 'Rephrase the request in a safe, constructive way.',
    );
  }

  ScanResult _scanCode(String text) {
    final m = _codePattern.allMatches(text).toList();
    if (m.isEmpty) {
      return const ScanResult(category: ScanCategory.maliciousCode);
    }
    return ScanResult(
      category: ScanCategory.maliciousCode,
      hit: true,
      confidence: min(1.0, 0.4 + m.length * 0.2),
      summary: 'Embedded script / injection code detected',
      detail: 'Detected constructs: ${m.map((x) => x.group(0)!.trim()).join(', ')}',
      suggestion: 'Run the code inside the T.B sandbox, never at top level.',
    );
  }

  double _levelOf(String text) {
    // rough proxy: length + density of suspicious tokens raises level
    return min(1.0, text.length / 2000);
  }

  double _levelThreshold(SecurityLevel level) => switch (level) {
        SecurityLevel.low => 0.9,
        SecurityLevel.medium => 0.6,
        SecurityLevel.high => 0.4,
        SecurityLevel.custom => 0.5,
      };

  bool _confidentEnough(bool hit, double score, double levelProbe) => hit &&
      score >= (levelProbe > 0.5 ? 0.5 : 0.33);

  static bool _startsWith(List<int> a, List<int> b) {
    if (b.length > a.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}