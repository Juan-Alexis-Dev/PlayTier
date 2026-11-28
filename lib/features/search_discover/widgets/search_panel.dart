import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/search_result.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../playlist/widgets/track_tile.dart';
import '../search_view_model.dart';

/// Search bar and result list with an "Add" button per track.
///
/// Shared by the Search & Discover tab and the "Add music" screen of a
/// playlist. Needs a [SearchViewModel] above it.
class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key, this.autofocus = false, this.idle});

  /// Opens the keyboard on the search bar (the "Add music" screen).
  final bool autofocus;

  /// Shown instead of the search hint while the search bar is empty
  /// (the Discover cards in the Search & Discover tab).
  final Widget? idle;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  static const _maxContentWidth = 960.0;

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _add(SearchViewModel vm, SearchResult item) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await vm.add(item);
    if (!mounted) return;
    final target = vm.targetName;
    final where = target == null ? 'your main playlist' : '"$target"';
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Added "${item.track.name}" to $where.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SearchViewModel>();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  controller: _searchController,
                  autoFocus: widget.autofocus,
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
    );
  }

  List<Widget> _content(SearchViewModel vm) {
    final idle = widget.idle;
    if (idle != null && vm.query.trim().isEmpty) {
      return [SliverToBoxAdapter(child: idle)];
    }

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
              done: vm.isDone(item),
              doneTooltip:
                  vm.hasTarget ? 'In this playlist' : 'In main playlist',
              addTooltip:
                  vm.hasTarget ? 'Add to this playlist' : 'Add to main playlist',
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
      return EmptyState(
        icon: Icons.search,
        message: vm.hasTarget
            ? 'Search Spotify for tracks to add to this playlist.'
            : 'Search Spotify by track, artist or album.',
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

/// "Add" button of a result: a check when there is nothing left to add,
/// a spinner while adding.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.done,
    required this.doneTooltip,
    required this.addTooltip,
    required this.adding,
    required this.onAdd,
  });

  final bool done;
  final String doneTooltip;
  final String addTooltip;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Tooltip(
        message: doneTooltip,
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
      tooltip: addTooltip,
      icon: const Icon(Icons.add_circle_outline),
      onPressed: onAdd,
    );
  }
}