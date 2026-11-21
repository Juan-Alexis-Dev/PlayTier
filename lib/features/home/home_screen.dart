import 'package:flutter/material.dart';

/// Home tab. Placeholder until v0.1 step 11 (Main/Liked cards + grid).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PlayTier')),
      body: const Center(child: Text('Home screen')),
    );
  }
}