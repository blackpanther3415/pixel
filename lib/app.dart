import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_services.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'shell/main_shell.dart';

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

class _PixelHome extends StatelessWidget {
  const _PixelHome();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return MainShell(appState: appState);
  }
}