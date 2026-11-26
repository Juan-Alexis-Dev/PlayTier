import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../filters/filter_sheet.dart';
import 'playlist_view_model.dart';
import 'widgets/action_row.dart';
import 'widgets/active_filters_bar.dart';
import 'widgets/level_filter_bar.dart';
import 'widgets/playlist_header.dart';
import 'widgets/sort_sheet.dart';
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
            SliverToBoxAdapter(
              child: ActionRow(
                onPlay: tracks.isEmpty || vm.starting ? null : vm.play,
                onShuffle: tracks.isEmpty || vm.starting ? null : vm.shuffle,
                onSort: vm.totalCount == 0
                    ? null
                    : () => SortSheet.show(
                          context,
                          current: vm.sort,
                          onSelected: vm.setSort,
                        ),
                onNewSubplaylist: vm.totalCount == 0
                    ? null
                    : () => _openFilters(context, vm),
              ),
            ),
            if (vm.isLiked && vm.totalCount > 0)
              SliverToBoxAdapter(
                child: LevelFilterBar(
                  levels: PlaylistViewModel.likedLevels,
                  shown: vm.shownLevels,
                  onToggle: vm.toggleLevel,
                ),
              ),
            if (vm.isCustomized)
              SliverToBoxAdapter(
                child: ActiveFiltersBar(
                  criteria: vm.criteria,
                  sort: vm.sort,
                  shown: tracks.length,
                  total: vm.totalCount,
                  onEditFilters: () => _openFilters(context, vm),
                  onClearFilters: vm.clearFilters,
                  onClearSort: () => vm.setSort(null),
                  onCreatePlaylist: tracks.isEmpty
                      ? null
                      : () => context.push(
                            AppRoutes.preview,
                            extra: vm.createDraft(),
                          ),
                ),
              ),
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
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _emptyMessage(vm),
                            textAlign: TextAlign.center,
                          ),
                        ),
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

  static String _emptyMessage(PlaylistViewModel vm) {
    if (vm.totalCount > 0) return 'No tracks match these filters.';
    return vm.isLiked
        ? 'No liked tracks yet. Give a track 2 or more stars in Now Playing.'
        : 'This playlist has no playable tracks.';
  }

  Future<void> _openFilters(BuildContext context, PlaylistViewModel vm) async {
    final criteria = await FilterSheet.show(context, vm.createFilterViewModel);
    if (criteria != null) vm.setFilters(criteria);
  }
}