import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/preset_palettes.dart';


class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlayTier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(PresetPalettes.defaultPalette),
      home: const Scaffold(
        body: Center(child: Text('PlayTier')),
      ),
    );
  }
}