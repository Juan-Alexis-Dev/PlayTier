import 'package:material_ui/material_ui.dart';

import 'search_view_model.dart';
import 'widgets/search_panel.dart';

/// Search & Discover tab: Spotify search with an "Add" button per result
/// (FR-9). Discover cards come in v0.6.
///
/// Needs a [SearchViewModel] above it (created by the route).
class SearchDiscoverScreen extends StatelessWidget {
  const SearchDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search & Discover')),
      body: const SearchPanel(),
    );
  }
}