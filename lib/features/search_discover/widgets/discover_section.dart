import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../domain/models/discover_mode.dart';
import '../../../shared/widgets/empty_state.dart';
import '../discover_view_model.dart';
import 'discover_card.dart';

/// "Want new music? Try these:" and the 2×2 grid of Discover cards.
///
/// Shown in the Search & Discover tab while the search bar is empty.
/// Needs a [DiscoverViewModel] above it.
class DiscoverSection extends StatelessWidget {
  const DiscoverSection({super.key});

  Future<void> _run(BuildContext context, DiscoverMode mode) async {
    final vm = context.read<DiscoverViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final draft = await vm.run(mode);
    if (!context.mounted) return;

    if (draft != null) {
      await context.push(AppRoutes.searchPreview, extra: draft);
      return;
    }
    final error = vm.errorMessage;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiscoverViewModel>();
    final theme = Theme.of(context);

    if (!vm.isAvailable) {
      return const EmptyState(
        icon: Icons.explore_off,
        message: 'Discover needs a Last.fm API key in config.json.',
      );
    }

    Widget card(DiscoverMode mode) => DiscoverCard(
          mode: mode,
          loading: vm.running == mode,
          comingSoon: !vm.isReady(mode),
          onTap: vm.canRun(mode) ? () => _run(context, mode) : null,
        );

    // Two rows of two cards with the same height (symmetric grid).
    Widget row(DiscoverMode a, DiscoverMode b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: card(a)),
              const SizedBox(width: 8),
              Expanded(child: card(b)),
            ],
          ),
        );

    const modes = DiscoverViewModel.cardModes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Want new music? Try these:', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          row(modes[0], modes[1]),
          const SizedBox(height: 8),
          row(modes[2], modes[3]),
        ],
      ),
    );
  }
}