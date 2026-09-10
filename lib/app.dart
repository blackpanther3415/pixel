import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_services.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'shell/main_shell.dart';
import 'widgets/onboarding_wizard.dart';

const _kOnboardingDone = 'pixel_onboarding_done';

class PixelApp extends StatelessWidget {
  final AppState appState;

  const PixelApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildPixelTheme(),
        home: const _PixelHome(),
      ),
    );
  }
}

class _PixelHome extends StatefulWidget {
  const _PixelHome();

  @override
  State<_PixelHome> createState() => _PixelHomeState();
}

class _PixelHomeState extends State<_PixelHome> {
  bool _onboarded = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_kOnboardingDone) ?? false;
    if (mounted) setState(() { _onboarded = done; _checking = false; });
  }

  void _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
    if (mounted) setState(() => _onboarded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_onboarded) {
      final appState = context.watch<AppState>();
      return OnboardingWizard(
        state: appState,
        onComplete: _completeOnboarding,
      );
    }
    final appState = context.watch<AppState>();
    return MainShell(appState: appState);
  }
}
