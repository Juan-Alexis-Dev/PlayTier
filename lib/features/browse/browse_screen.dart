import 'package:material_ui/material_ui.dart';

/// Content shown by [BrowseScreen].
enum BrowseKind { genres, artists }

/// Genres and Artists tabs (same layout). Placeholder until v0.4.
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key, required this.kind});

  final BrowseKind kind;

  @override
  Widget build(BuildContext context) {
    final title = switch (kind) {
      BrowseKind.genres => 'Genres',
      BrowseKind.artists => 'Artists',
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title screen')),
    );
  }
}