import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';

/// Home tab. Placeholder until v0.1 step 11 (Main/Liked cards + grid).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PlayTier')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Home screen'),
            const SizedBox(height: 16),
            // TEMP until step 11: the Main playlist card replaces it.
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.mainPlaylist),
              icon: const Icon(Icons.library_music),
              label: const Text('Open main playlist'),
            ),
          ],
        ),
      ),
    );
  }
}