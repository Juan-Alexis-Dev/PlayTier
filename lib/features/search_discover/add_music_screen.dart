import 'package:material_ui/material_ui.dart';

import 'search_view_model.dart';
import 'widgets/search_panel.dart';

/// Playlist that "Add music" fills, passed to the route as `extra`.
class AddMusicTarget {
  const AddMusicTarget({
    required this.name,
    this.playlistId,
    this.trackIds = const {},
  });

  /// Playlist name, for the title and messages.
  final String name;

  /// Spotify id of a permanent playlist; null for the main playlist.
  final String? playlistId;

  /// Tracks already in the playlist, shown as added.
  final Set<String> trackIds;
}

/// "Add music" of a playlist (FR-9.4): the search, adding to that
/// playlist and to the main playlist.
///
/// Needs a [SearchViewModel] above it (created by the route).
class AddMusicScreen extends StatelessWidget {
  const AddMusicScreen({super.key, required this.target});

  final AddMusicTarget target;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add to ${target.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: const SearchPanel(autofocus: true),
    );
  }
}