import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/preset_palettes.dart';

/// Root widget. Reads the active palette from `SettingsViewModel` later.
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // Created once so hot reload and rebuilds keep the navigation state.
  late final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PlayTier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(PresetPalettes.defaultPalette),
      routerConfig: _router,
    );
  }
}