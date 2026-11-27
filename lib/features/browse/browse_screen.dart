import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/card_grid.dart';
import '../../shared/widgets/cover_mosaic.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/playlist_card.dart';
import 'browse_view_model.dart';

/// Content shown by [BrowseScreen].
enum BrowseKind { genres, artists }

/// Genres and Artists tabs: search bar on top, then a symmetric grid of
/// virtual playlist cards (name, track count, cover mosaic).
///
/// Needs a [BrowseViewModel] above it (created by the route).
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.kind, this.onOpen});

  final BrowseKind kind;

  /// Called when a card is tapped (opens the virtual playlist).
  final void Function(BrowseItem item)? onOpen;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const _maxContentWidth = 960.0;

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BrowseViewModel>();
    final (title, noun, icon) = switch (widget.kind) {
      BrowseKind.genres => ('Genres', 'genres', Icons.category),
      BrowseKind.artists => ('Artists', 'artists', Icons.person),
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Search $noun',
                    leading: const Icon(Icons.search),
                    onChanged: vm.setQuery,
                    trailing: [
                      if (vm.query.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            vm.setQuery('');
                          },
                        ),
                    ],
                  ),
                ),
              ),
              _content(vm, noun, icon),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BrowseViewModel vm, String noun, IconData icon) {
    final message = _message(vm, noun, icon);
    if (message != null) {
      return SliverPadding(
        padding: const EdgeInsets.all(24),
        sliver: SliverToBoxAdapter(child: Center(child: message)),
      );
    }

    final items = vm.items;
    final onOpen = widget.onOpen;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: CardGrid(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return PlaylistCard(
            artwork: CoverMosaic(
              item.coverUrls,
              size: double.infinity,
              borderRadius: 0,
            ),
            title: item.name,
            subtitle:
                item.trackCount == 1 ? '1 track' : '${item.trackCount} tracks',
            onTap: onOpen == null ? null : () => onOpen(item),
          );
        },
      ),
    );
  }

  /// Loading, error or empty message; null when the grid has items.
  Widget? _message(BrowseViewModel vm, String noun, IconData icon) {
    final error = vm.errorMessage;
    if (vm.loading) return const CircularProgressIndicator();
    if (error != null) {
      return EmptyState(icon: Icons.error_outline, message: error);
    }
    if (vm.totalCount == 0) {
      return EmptyState(
        icon: icon,
        message: 'No $noun yet. They appear after syncing your main '
            'playlist from Home.',
      );
    }
    if (vm.items.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: 'No $noun match "${vm.query.trim()}".',
      );
    }
    return null;
  }
}