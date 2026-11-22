import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'playlist_view_model.dart';
import 'widgets/action_row.dart';
import 'widgets/playlist_header.dart';
import 'widgets/track_tile.dart';

/// Spotify-like playlist view: header, action row and track list.
class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlaylistViewModel>();
    final theme = Theme.of(context);
    final error = vm.errorMessage;
    final tracks = vm.tracks;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Check for changes',
            onPressed: vm.syncing ? null : vm.sync,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: vm.syncing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: vm.sync,
        child: CustomScrollView(
          // Lets pull-to-refresh work even with a short list.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: PlaylistHeader(
                name: vm.name,
                coverUrl: vm.coverUrl,
                trackCount: tracks.length,
                totalDuration: vm.totalDuration,
              ),
            ),
            const SliverToBoxAdapter(child: ActionRow()),
            if (error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: !vm.loaded || vm.syncing
                      ? const CircularProgressIndicator()
                      : const Text('This playlist has no playable tracks.'),
                ),
              )
            else
              SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    artists: vm.artistsOf(track),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}