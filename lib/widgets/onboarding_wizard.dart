import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';

class OnboardingWizard extends StatefulWidget {
  final AppState state;
  final VoidCallback onComplete;

  const OnboardingWizard({
    super.key,
    required this.state,
    required this.onComplete,
  });

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  final _pageController = PageController();
  final _openaiKeyController = TextEditingController();
  final _anthropicKeyController = TextEditingController();
  final _googleKeyController = TextEditingController();
  final _mistralKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _passphraseConfirmController = TextEditingController();

  int _currentPage = 0;
  String _securityLevel = 'medium';
  bool _vaultEnabled = false;
  bool _saving = false;

  static const _securityLevels = [
    (
      id: 'low',
      label: 'Low',
      description: 'Minimal content filtering. Faster responses, less restriction.',
      icon: Icons.shield_outlined,
      color: AppColors.accent,
    ),
    (
      id: 'medium',
      label: 'Medium',
      description: 'Balanced filtering and safety checks. Recommended for most users.',
      icon: Icons.shield,
      color: AppColors.primary,
    ),
    (
      id: 'high',
      label: 'High',
      description: 'Strict content filtering and security scanning on all messages.',
      icon: Icons.shield_rounded,
      color: AppColors.warn,
    ),
    (
      id: 'custom',
      label: 'Custom',
      description: 'Configure individual security policies manually after setup.',
      icon: Icons.tune,
      color: AppColors.textMid,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _openaiKeyController.dispose();
    _anthropicKeyController.dispose();
    _googleKeyController.dispose();
    _mistralKeyController.dispose();
    _passphraseController.dispose();
    _passphraseConfirmController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _complete() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final db = widget.state.services.db;
      final vault = widget.state.services.vault;
      final gateway = widget.state.services.gateway;

      var settings = await db.getSettings();
      settings = settings.copyWith(
        securityLevel: _securityLevel,
        vaultEnabled: _vaultEnabled,
      );

      if (_vaultEnabled && _passphraseController.text.isNotEmpty) {
        await vault.unlock(_passphraseController.text);
        settings = settings.copyWith(vaultSalt: vault.saltB64);
      }

      if (_securityLevel != 'custom') {
        settings = settings.copyWith(securityLevel: _securityLevel);
      }

      await db.saveSettings(settings);
      gateway.loadLevel(settings);

      final providers = <Map<String, String>>[
        if (_openaiKeyController.text.trim().isNotEmpty)
          {'id': 'openai', 'key': _openaiKeyController.text.trim()},
        if (_anthropicKeyController.text.trim().isNotEmpty)
          {'id': 'anthropic', 'key': _anthropicKeyController.text.trim()},
        if (_googleKeyController.text.trim().isNotEmpty)
          {'id': 'google', 'key': _googleKeyController.text.trim()},
        if (_mistralKeyController.text.trim().isNotEmpty)
          {'id': 'mistral', 'key': _mistralKeyController.text.trim()},
      ];

      for (final p in providers) {
        final encrypted = await vault.maybeEncrypt(p['key']!);
        await db.db.rawUpdate(
          'UPDATE providers SET api_key = ? WHERE id = ?',
          [encrypted, p['id']],
        );
      }

      if (providers.isNotEmpty) {
        settings = settings.copyWith(defaultProviderId: providers.first['id']);
        await db.saveSettings(settings);
      }

      widget.onComplete();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _prevPage();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              if (_currentPage > 0 && _currentPage < 3)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
                    child: TextButton.icon(
                      onPressed: _prevPage,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMid,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _buildWelcomePage(),
                    _buildSecurityPage(),
                    _buildProviderPage(),
                    _buildCompletionPage(),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDotIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final active = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDotIndicator(),
          const SizedBox(height: 20),
          if (_currentPage == 0)
            _buildPrimaryButton('Get Started', _nextPage)
          else if (_currentPage == 1)
            _buildPrimaryButton('Continue', _nextPage)
          else if (_currentPage == 2) ...[
            _buildPrimaryButton(
              _saving ? 'Saving...' : 'Finish Setup',
              _saving ? null : _complete,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      _nextPage();
                      _complete();
                    },
              child: const Text(
                'Skip for now',
                style: TextStyle(color: AppColors.textMid),
              ),
            ),
          ] else
            _buildPrimaryButton('Start Using Pixel', _saving ? null : _complete),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textHigh,
          disabledBackgroundColor: AppColors.surfaceLight,
          disabledForegroundColor: AppColors.textLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _saving && label != 'Saving...'
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textHigh,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: Text(
                'P',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textHigh,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Welcome to Pixel',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your private AI OS. Everything runs locally\nwith end-to-end encryption and full control.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.textMid,
            ),
          ),
          const SizedBox(height: 40),
          _buildInfoCard(
            icon: Icons.lock_outline,
            title: 'Local-First',
            description: 'All data stays on your device by default.',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.speed,
            title: 'Multi-Provider',
            description: 'Use OpenAI, Anthropic, Google, and more.',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.psychology,
            title: 'Smart Security',
            description: 'Built-in G.B. security gateway protects every prompt.',
          ),
          const SizedBox(height: 32),
          _buildVaultSection(),
        ],
      ),
    );
  }

  Widget _buildVaultSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _vaultEnabled ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.enhanced_encryption,
                color: _vaultEnabled ? AppColors.accent : AppColors.textMid,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Vault Encryption',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHigh,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _vaultEnabled,
                onChanged: (v) => setState(() => _vaultEnabled = v),
                activeTrackColor: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Encrypt API keys and sensitive data with a passphrase. '
            'You will need to enter it each time you start Pixel.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textMid,
            ),
          ),
          if (_vaultEnabled) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _passphraseController,
              obscureText: true,
              obscuringCharacter: '\u2022',
              style: const TextStyle(color: AppColors.textHigh),
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                hintText: 'At least 6 characters',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphraseConfirmController,
              obscureText: true,
              obscuringCharacter: '\u2022',
              style: const TextStyle(color: AppColors.textHigh),
              decoration: InputDecoration(
                labelText: 'Confirm Passphrase',
                hintText: 'Re-enter passphrase',
                errorText: _passphraseController.text.isNotEmpty &&
                        _passphraseConfirmController.text.isNotEmpty &&
                        _passphraseController.text !=
                            _passphraseConfirmController.text
                    ? 'Passphrases do not match'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 48),
          const Text(
            'Security Level',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pixel\'s G.B. Gateway filters and scans every\nprompt and response in real time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textMid,
            ),
          ),
          const SizedBox(height: 32),
          ..._securityLevels.map((level) {
            final selected = _securityLevel == level.id;
            return GestureDetector(
              onTap: () => setState(() => _securityLevel = level.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: selected ? AppColors.surfaceLight : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? level.color : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? level.color.withValues(alpha: 0.15)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        level.icon,
                        color: selected ? level.color : AppColors.textMid,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AppColors.textHigh
                                  : AppColors.textMid,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            level.description,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppColors.textLow,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        color: level.color,
                        size: 22,
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProviderPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'Provider Setup',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add at least one API key to start using Pixel.\nYou can add more later in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textMid,
            ),
          ),
          const SizedBox(height: 28),
          _buildProviderField(
            controller: _openaiKeyController,
            label: 'OpenAI',
            hint: 'sk-...',
            color: AppColors.good,
          ),
          const SizedBox(height: 14),
          _buildProviderField(
            controller: _anthropicKeyController,
            label: 'Anthropic',
            hint: 'sk-ant-...',
            color: const Color(0xFFD4A574),
          ),
          const SizedBox(height: 14),
          _buildProviderField(
            controller: _googleKeyController,
            label: 'Google Gemini',
            hint: 'AI...',
            color: AppColors.accent,
          ),
          const SizedBox(height: 14),
          _buildProviderField(
            controller: _mistralKeyController,
            label: 'Mistral',
            hint: 'mist-...',
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildProviderField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color color,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(
        color: AppColors.textHigh,
        fontFamily: 'monospace',
        fontSize: 14,
      ),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(Icons.key, color: color, size: 18),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                color: AppColors.textLow,
                onPressed: () {
                  controller.clear();
                  setState(() {});
                },
              )
            : null,
        labelStyle: TextStyle(color: color),
      ),
    );
  }

  Widget _buildCompletionPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 64),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.good.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.good,
              size: 44,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'You\'re All Set',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pixel is configured and ready to go.\nHere\'s a summary of your setup.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textMid,
            ),
          ),
          const SizedBox(height: 36),
          _buildSummaryRow(
            Icons.shield,
            'Security Level',
            _securityLevel[0].toUpperCase() + _securityLevel.substring(1),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(
            Icons.enhanced_encryption,
            'Vault',
            _vaultEnabled ? 'Enabled' : 'Disabled',
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(
            Icons.key,
            'Providers',
            _configuredProviderCount > 0
                ? '$_configuredProviderCount configured'
                : 'None (add in Settings)',
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  int get _configuredProviderCount {
    int count = 0;
    if (_openaiKeyController.text.trim().isNotEmpty) count++;
    if (_anthropicKeyController.text.trim().isNotEmpty) count++;
    if (_googleKeyController.text.trim().isNotEmpty) count++;
    if (_mistralKeyController.text.trim().isNotEmpty) count++;
    return count;
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textMid,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textHigh,
            ),
          ),
        ],
      ),
    );
  }
}
