import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../domain/models/search_result.dart';
import '../../shared/widgets/empty_state.dart';
import '../playlist/widgets/track_tile.dart';
import 'search_view_model.dart';

/// Search & Discover tab: Spotify search with an "Add" button per result
/// (FR-9). Discover cards come in v0.6.
///
/// Needs a [SearchViewModel] above it (created by the route).
class SearchDiscoverScreen extends StatefulWidget {
  const SearchDiscoverScreen({super.key});

  @override
  State<SearchDiscoverScreen> createState() => _SearchDiscoverScreenState();
}

class _SearchDiscoverScreenState extends State<SearchDiscoverScreen> {
  static const _maxContentWidth = 960.0;

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _add(SearchViewModel vm, SearchResult item) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await vm.add(item);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Added "${item.track.name}" to your main playlist.'
              : 'Could not add the track. Try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SearchViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Search & Discover')),
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
                    hintText: 'Search tracks, artists or albums',
                    leading: const Icon(Icons.search),
                    textInputAction: TextInputAction.search,
                    onChanged: vm.setQuery,
                    onSubmitted: (_) => vm.submit(),
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
              ..._content(vm),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(SearchViewModel vm) {
    final message = _message(vm);
    if (message != null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverToBoxAdapter(child: Center(child: message)),
        ),
      ];
    }

    final results = vm.results;
    return [
      SliverList.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final item = results[index];
          return TrackTile(
            track: item.track,
            artists: item.artistNames.join(', '),
            action: _AddButton(
              inMain: item.inMain,
              adding: vm.isAdding(item.track.id),
              onAdd: () => _add(vm, item),
            ),
          );
        },
      ),
      if (vm.hasMore)
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: vm.loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: vm.loadMore,
                      child: const Text('Load more'),
                    ),
            ),
          ),
        ),
    ];
  }

  /// Hint, loading, error or "no results"; null when there are results.
  Widget? _message(SearchViewModel vm) {
    final error = vm.errorMessage;
    if (vm.query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        message: 'Search Spotify by track, artist or album.',
      );
    }
    if (vm.loading) return const CircularProgressIndicator();
    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(icon: Icons.error_outline, message: error),
          FilledButton.tonal(
            onPressed: vm.submit,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (vm.hasSearched && vm.results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: 'No results for "${vm.query.trim()}".',
      );
    }
    // Typing, waiting for the debounce: nothing to show yet.
    if (vm.results.isEmpty) return const SizedBox.shrink();
    return null;
  }
}

/// "Add" button of a result: a check when the track is already in the
/// main playlist, a spinner while adding.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.inMain,
    required this.adding,
    required this.onAdd,
  });

  final bool inMain;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (inMain) {
      return Tooltip(
        message: 'In main playlist',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    if (adding) {
      return const SizedBox.square(
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Add to main playlist',
      icon: const Icon(Icons.add_circle_outline),
      onPressed: onAdd,
    );
  }
}