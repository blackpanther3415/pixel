import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../models/provider.dart';
import '../models/security_event.dart';
import '../services/database/database_service.dart';
import '../services/vault/vault_service.dart';

/// Global settings: provider API keys, security/routing defaults, budget, vault.
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
  String? _vaultError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.state.services.db;
    final providers = await db.listProviders();
    final settings = await db.getSettings();
    final vault = widget.state.services.vault;
    setState(() {
      _providers = providers;
      _settings = settings;
      for (final p in providers) {
        // Decrypt API keys if vault is unlocked
        final rawKey = p.apiKey ?? '';
        if (rawKey.isNotEmpty && vault.hasSalt && !vault.isLocked) {
          vault.maybeDecrypt(rawKey).then((dec) {
            if (mounted) {
              setState(() {
                _keys[p.id] = TextEditingController(text: dec);
              });
            }
          });
        } else {
          _keys[p.id] = TextEditingController(text: rawKey);
        }
        _urls[p.id] = TextEditingController(text: p.baseUrl ?? '');
        _enabled[p.id] = p.enabled;
      }
    });
  }

  Future<void> _save() async {
    final db = widget.state.services.db;
    final vault = widget.state.services.vault;
    final providers = _providers ?? const <ProviderConfig>[];
    for (final p in providers) {
      String? apiKey = _keys[p.id]?.text.trim();
      if (apiKey != null && apiKey.isNotEmpty) {
        // Encrypt through vault before persisting
        apiKey = await vault.maybeEncrypt(apiKey);
      } else {
        apiKey = p.apiKey;
      }
      final updated = p.copyWith(
        apiKey: apiKey,
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

  Future<void> _vaultSetup() async {
    final passphraseCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('Set up vault',
            style: TextStyle(color: AppColors.textHigh)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose a passphrase to encrypt all API keys. '
              'If you lose it, keys cannot be recovered.',
              style: TextStyle(color: AppColors.textMid, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passphraseCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, passphraseCtrl.text),
            child: const Text('Enable vault'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final vault = widget.state.services.vault;
    await vault.unlock(result);
    final s = _settings ?? const AppSettings();
    _settings = s.copyWith(
      vaultEnabled: true,
      vaultSalt: vault.saltB64,
    );
    setState(() => _vaultError = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vault enabled. API keys are now encrypted.')),
    );
  }

  Future<void> _vaultUnlock() async {
    final passphraseCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('Unlock vault',
            style: TextStyle(color: AppColors.textHigh)),
        content: TextField(
          controller: passphraseCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
            prefixIcon: Icon(Icons.lock_open),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, passphraseCtrl.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final vault = widget.state.services.vault;
    final ok = await vault.unlock(result);
    if (ok) {
      setState(() => _vaultError = null);
      _load(); // re-decrypt keys
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault unlocked.')),
      );
    } else {
      setState(() => _vaultError = 'Wrong passphrase.');
    }
  }

  void _vaultLock() {
    widget.state.services.vault.lock();
    setState(() => _vaultError = null);
    _load(); // reload (keys will appear encrypted)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vault locked.')),
    );
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
    final vault = widget.state.services.vault;
    final vaultActive = _settings!.vaultEnabled;
    return AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      insetPadding: const EdgeInsets.all(20),
      title: const Text('Pixel settings',
          style: TextStyle(color: AppColors.textHigh)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vault section
              _vaultSection(vaultActive, vault),
              const SizedBox(height: 14),
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
                        widget.state.services.gateway.loadLevel(_settings!);
                      }),
              ),
              const SizedBox(height: 8),
              TextField(
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

  Widget _vaultSection(bool vaultActive, VaultService vault) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: vaultActive
            ? AppColors.good.withValues(alpha: 0.08)
            : AppColors.warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: vaultActive
                ? AppColors.good.withValues(alpha: 0.3)
                : AppColors.warn.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                vaultActive
                    ? (vault.isLocked ? Icons.lock : Icons.lock_open)
                    : Icons.lock_open,
                size: 18,
                color: vaultActive
                    ? (vault.isLocked ? AppColors.warn : AppColors.good)
                    : AppColors.textLow,
              ),
              const SizedBox(width: 8),
              Text(
                vaultActive
                    ? (vault.isLocked ? 'Vault locked' : 'Vault unlocked')
                    : 'Vault disabled',
                style: const TextStyle(
                    color: AppColors.textHigh, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (!vaultActive)
                TextButton(
                  onPressed: _vaultSetup,
                  child: const Text('Enable vault'),
                )
              else ...[
                if (vault.isLocked)
                  TextButton(
                    onPressed: _vaultUnlock,
                    child: const Text('Unlock'),
                  )
                else
                  TextButton(
                    onPressed: _vaultLock,
                    child: const Text('Lock'),
                  ),
              ],
            ],
          ),
          if (!vaultActive)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Encrypts API keys at rest. Without a passphrase, keys '
                'are stored as plaintext in SQLite.',
                style: TextStyle(color: AppColors.textLow, fontSize: 11),
              ),
            ),
          if (vaultActive)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'All API keys are encrypted with AES-256-GCM.',
                style: TextStyle(color: AppColors.textLow, fontSize: 11),
              ),
            ),
          if (_vaultError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_vaultError!,
                  style: const TextStyle(color: AppColors.bad, fontSize: 12)),
            ),
        ],
      ),
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
                      color: AppColors.textHigh,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(p.kind.name,
                  style: const TextStyle(
                      color: AppColors.textLow, fontSize: 11)),
            ],
          ),
          TextField(
            controller: _keys[p.id],
            obscureText: true,
            enabled: _enabled[p.id] ?? true,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: (p.apiKey?.isNotEmpty ?? false)
                  ? '••••encrypted'
                  : 'sk-…',
            ),
          ),
          if (p.kind == ProviderKind.ollama ||
              p.kind == ProviderKind.local) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _urls[p.id],
              enabled: _enabled[p.id] ?? true,
              decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://localhost:11434'),
            ),
          ],
        ],
      ),
    );
  }
}
