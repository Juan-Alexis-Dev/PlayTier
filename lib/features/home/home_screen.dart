import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../domain/models/playlist_summary.dart';
import '../../shared/widgets/card_grid.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/playlist_card.dart';
import 'home_view_model.dart';

/// Home: Main and Liked cards, then the "Your playlists" grid.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _maxContentWidth = 960.0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final theme = Theme.of(context);
    final syncError = vm.syncError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlayTier'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: vm.syncing || vm.loadingPlaylists ? null : vm.refresh,
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
        onRefresh: vm.refresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(child: _MainCards(vm)),
                ),
                if (syncError != null)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        syncError,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Your playlists',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                _PlaylistsGrid(vm),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two large cards, side by side (symmetric layout).
class _MainCards extends StatelessWidget {
  const _MainCards(this.vm);

  final HomeViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PlaylistCard(
              large: true,
              artwork: CoverImage(vm.mainCoverUrl, size: double.infinity),
              title: vm.mainName,
              subtitle: '${vm.trackCount} tracks',
              onTap: () => context.go(AppRoutes.mainPlaylist),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: PlaylistCard(
              large: true,
              artwork: ColoredBox(
                color: colorScheme.primaryContainer,
                child: Icon(
                  Icons.favorite,
                  size: 64,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              title: 'Liked',
              subtitle: '${vm.likedCount} tracks · levels 2–5',
              onTap: () => context.go(AppRoutes.liked),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistsGrid extends StatelessWidget {
  const _PlaylistsGrid(this.vm);

  final HomeViewModel vm;

  @override
  Widget build(BuildContext context) {
    final playlists = vm.playlists;
    final error = vm.playlistsError;

    if (playlists.isEmpty) {
      final Widget child;
      if (vm.loadingPlaylists) {
        child = const CircularProgressIndicator();
      } else if (error != null) {
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: vm.loadPlaylists,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        );
      } else {
        child = const Text(
          'Playlists you create with PlayTier will appear here.',
          textAlign: TextAlign.center,
        );
      }
      return SliverPadding(
        padding: const EdgeInsets.all(24),
        sliver: SliverToBoxAdapter(child: Center(child: child)),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: CardGrid(
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return PlaylistCard(
            artwork: CoverImage(playlist.coverUrl, size: double.infinity),
            title: playlist.name,
            subtitle: _subtitle(playlist),
            onTap: () => context.go(AppRoutes.playlist(playlist.id)),
          );
        },
      ),
    );
  }

  static String _subtitle(PlaylistSummary playlist) {
    final kind =
        playlist.type == PlaylistType.permanent ? 'PlayTier' : 'Spotify';
    return playlist.trackCount > 0
        ? '$kind · ${playlist.trackCount} tracks'
        : kind;
  }
}