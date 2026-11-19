import 'package:flutter/material.dart';

/// Root widget of PlayTier.
///
/// Placeholder until the theme system (step 4) and the router (step 5) exist;
/// then it becomes a MaterialApp.router with the active palette.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PlayTier',
      home: Scaffold(
        body: Center(child: Text('PlayTier')),
      ),
    );
  }
}
