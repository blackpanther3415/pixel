import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../models/security_event.dart';
import '../../widgets/common.dart';

/// G.B — Security Gateway. Everything in/out of Pixel transits here.
class SecurityTab extends StatefulWidget {
  final AppState state;
  const SecurityTab({super.key, required this.state});

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  late Future<_GbData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_GbData> _load() async {
    final g = widget.state.services.gateway;
    final db = widget.state.services.db;
    final settings = await db.getSettings();
    g.loadLevel(settings);
    final events = await db.listSecurityEvents();
    final stats = await db.securityStats();
    final quarantine = await db.listQuarantine();
    return _GbData(
      level: g.level,
      events: events,
      stats: stats,
      quarantine: quarantine,
    );
  }

  Future<void> _setLevel(SecurityLevel l) async {
    final g = widget.state.services.gateway;
    final db = widget.state.services.db;
    final s = await db.getSettings();
    await db.saveSettings(s.copyWith(securityLevel: l.name));
    g.level = l;
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GbData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        final blocked = (d.stats['block'] ?? 0) +
            (d.stats['quarantine'] ?? 0);
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _LevelCard(level: d.level, onSelect: _setLevel),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount:
                    MediaQuery.of(context).size.width > 700 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.9,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  const StatCard(
                    label: 'Gate mode',
                    value: 'G.B ACTIVE',
                    icon: Icons.verified_user,
                    color: AppColors.good,
                  ),
                  StatCard(
                    label: 'Blocked',
                    value: '$blocked',
                    icon: Icons.block,
                    color: AppColors.bad,
                  ),
                  StatCard(
                    label: 'Passed',
                    value: '${d.stats['pass'] ?? 0}',
                    icon: Icons.check_circle,
                    color: AppColors.good,
                  ),
                  StatCard(
                    label: 'Events',
                    value: '${d.events.length}',
                    icon: Icons.notifications,
                    color: AppColors.warn,
                  ),
                ],
              ),
              const SectionHeader('Live security log'),
              if (d.events.isEmpty)
                const EmptyState(
                  icon: Icons.shield,
                  title: 'No events yet',
                  message:
                      'All traffic passing through G.B is audited here. '
                      'Clean so far.',
                )
              else
                ...d.events.map(
                  (e) => _EventTile(e),
                ),
              const SectionHeader('Quarantine'),
              if (d.quarantine.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Nothing quarantined.',
                      style: TextStyle(color: AppColors.textMid)),
                )
              else
                ...d.quarantine.map((q) => _QuarantineTile(q)),
            ],
          ),
        );
      },
    );
  }
}

class _LevelCard extends StatelessWidget {
  final SecurityLevel level;
  final ValueChanged<SecurityLevel> onSelect;
  const _LevelCard({required this.level, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.shield, color: AppColors.primaryLight),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Security level',
                      style: TextStyle(color: AppColors.textMid, fontSize: 12)),
                  Text('All input/output data passes through this gateway',
                      style: TextStyle(color: AppColors.textLow, fontSize: 11)),
                ],
              ),
            ),
            DropdownButton<SecurityLevel>(
              value: level,
              dropdownColor: AppColors.surfaceLight,
              style: const TextStyle(color: AppColors.textHigh),
              underline: const SizedBox.shrink(),
              items: SecurityLevel.values
                  .map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(l.name.toUpperCase())))
                  .toList(),
              onChanged: (v) => v != null ? onSelect(v) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SecurityEvent e;
  const _EventTile(this.e);

  Color get _color => switch (e.verdict) {
        SecurityVerdict.block => AppColors.bad,
        SecurityVerdict.quarantine => AppColors.warn,
        SecurityVerdict.pass => AppColors.good,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              e.verdict == SecurityVerdict.pass
                  ? Icons.check_circle_outline
                  : Icons.gpp_maybe,
              color: _color,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(e.summary.isNotEmpty ? e.summary : e.category.name,
                          style: const TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(e.timeLabel,
                          style: const TextStyle(
                              color: AppColors.textLow, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(e.detail,
                      style: const TextStyle(
                          color: AppColors.textMid, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Chip(e.verdict.name, _color),
                      _Chip(e.direction, AppColors.textMid),
                      _Chip('${(e.confidence * 100).round()}%',
                          AppColors.textMid),
                      if (e.route != null) _Chip('via ${e.route}', AppColors.textLow),
                      if (e.suggestion != null && e.verdict != SecurityVerdict.pass)
                        Text('Safe option: ${e.suggestion}',
                            style: const TextStyle(
                                color: AppColors.good, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

class _QuarantineTile extends StatelessWidget {
  final Map<String, Object?> q;
  const _QuarantineTile(this.q);

  @override
  Widget build(BuildContext context) {
    final original = (q['original'] as String?) ?? '';
    final shown = original.length <= 220 ? original : '${original.substring(0, 217)}…';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.archive, color: AppColors.warn),
        title: const Text('Quarantined',
            style: TextStyle(
                color: AppColors.textHigh, fontWeight: FontWeight.w600)),
        subtitle: Text(shown,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
      ),
    );
  }
}

class _GbData {
  final SecurityLevel level;
  final List<SecurityEvent> events;
  final Map<String, int> stats;
  final List<Map<String, Object?>> quarantine;
  const _GbData({
    required this.level,
    required this.events,
    required this.stats,
    required this.quarantine,
  });
}