import 'package:material_ui/material_ui.dart';

import 'discover_view_model.dart';
import 'search_view_model.dart';
import 'widgets/discover_section.dart';
import 'widgets/search_panel.dart';

/// Search & Discover tab: Spotify search with an "Add" button per result
/// (FR-9) and, while the search bar is empty, the Discover cards (FR-10).
///
/// Needs a [SearchViewModel] and a [DiscoverViewModel] above it (created
/// by the route).
class SearchDiscoverScreen extends StatelessWidget {
  const SearchDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search & Discover')),
      body: const SearchPanel(idle: DiscoverSection()),
    );
  }
}