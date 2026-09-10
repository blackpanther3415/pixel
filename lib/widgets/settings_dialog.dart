import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../models/provider.dart';
import '../models/security_event.dart';
import '../services/database/database_service.dart';

/// Global settings: provider API keys, security/routing defaults, budget.
class SettingsDialog extends StatefulWidget {
  final AppState state;
  const SettingsDialog({super.key, required this.state});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();

  static Future<void> show(BuildContext context, AppState state) {
    return showDialog(
      context: context,
      builder: (_) => SettingsDialog(state: state),
    );
  }
}

class _SettingsDialogState extends State<SettingsDialog> {
  List<ProviderConfig>? _providers;
  AppSettings? _settings;
  final Map<String, TextEditingController> _keys = {};
  final Map<String, TextEditingController> _urls = {};
  final Map<String, bool> _enabled = {};
  final Map<String, bool> _touched = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.state.services.db;
    final providers = await db.listProviders();
    final settings = await db.getSettings();
    setState(() {
      _providers = providers;
      _settings = settings;
      for (final p in providers) {
        _keys[p.id] = TextEditingController(text: p.apiKey ?? '');
        _urls[p.id] = TextEditingController(text: p.baseUrl ?? '');
        _enabled[p.id] = p.enabled;
      }
    });
  }

  Future<void> _save() async {
    final db = widget.state.services.db;
    final providers = _providers ?? const <ProviderConfig>[];
    for (final p in providers) {
      final updated = p.copyWith(
        apiKey: _keys[p.id]?.text.trim().isNotEmpty == true
            ? _keys[p.id]!.text.trim()
            : p.apiKey,
        baseUrl: _urls[p.id]?.text.trim().isNotEmpty == true
            ? _urls[p.id]!.text.trim()
            : p.baseUrl,
        enabled: _enabled[p.id] ?? p.enabled,
      );
      await db.upsertProvider(updated);
    }
    final s = _settings ?? const AppSettings();
    await db.saveSettings(s);
    await widget.state.refresh();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    if (providers == null || _settings == null) {
      return const AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        content: SizedBox(
            width: 320, child: Center(child: CircularProgressIndicator())),
      );
    }
    return AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      insetPadding: const EdgeInsets.all(20),
      title: const Text('Pixel settings',
          style: TextStyle(color: AppColors.textHigh)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Providers — API keys stay on this device',
                  style: TextStyle(
                      color: AppColors.textMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final p in providers) _providerTile(p),
              const SizedBox(height: 14),
              const Text('Defaults',
                  style: TextStyle(
                      color: AppColors.textMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _settings!.routingMode,
                dropdownColor: AppColors.surfaceLight,
                decoration: const InputDecoration(labelText: 'Smart routing'),
                items: const [
                  DropdownMenuItem(value: 'cheapest', child: Text('Cheapest')),
                  DropdownMenuItem(value: 'fastest', child: Text('Fastest')),
                ],
                onChanged: (v) => v == null
                    ? null
                    : setState(() =>
                        _settings = _settings!.copyWith(routingMode: v)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _settings!.securityLevel,
                dropdownColor: AppColors.surfaceLight,
                decoration: const InputDecoration(labelText: 'G.B level'),
                items: SecurityLevel.values
                    .map((l) => DropdownMenuItem(
                        value: l.name, child: Text(l.name.toUpperCase())))
                    .toList(),
                onChanged: (v) => v == null
                    ? null
                    : setState(() {
                        _settings = _settings!.copyWith(securityLevel: v);
                        widget.state.services.gateway.loadLevel(
                            _settings!);
                      }),
              ),
              const SizedBox(height: 8),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Monthly budget (USD)'),
                onChanged: (v) => setState(() => _settings = _settings!
                    .copyWith(monthlyBudgetUsd: double.tryParse(v) ?? 0)),
                controller: TextEditingController(
                    text: _settings!.monthlyBudgetUsd.toString()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _providerTile(ProviderConfig p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(
                value: _enabled[p.id] ?? true,
                onChanged: (v) => setState(() => _enabled[p.id] = v),
              ),
              const SizedBox(width: 8),
              Text(p.name,
                  style: const TextStyle(
                      color: AppColors.textHigh, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(p.kind.name,
                  style:
                      const TextStyle(color: AppColors.textLow, fontSize: 11)),
            ],
          ),
          TextField(
            controller: _keys[p.id],
            obscureText: true,
            enabled: _enabled[p.id] ?? true,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: (p.apiKey?.isNotEmpty ?? false)
                  ? '••••${(p.apiKey!.length / 2).floor()}'
                  : 'sk-…',
              suffixIcon: IconButton(
                icon: Icon(_touched[p.id] == false
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () {}, // reveal via keyboard; keep simple
              ),
            ),
          ),
          if (p.kind == ProviderKind.ollama ||
              p.kind == ProviderKind.local) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _urls[p.id],
              enabled: _enabled[p.id] ?? true,
              decoration: const InputDecoration(
                  labelText: 'Server URL', hintText: 'http://localhost:11434'),
            ),
          ],
        ],
      ),
    );
  }
}