import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../shared/widgets/cover_image.dart';
import 'player_view_model.dart';

/// Bar with the current track and basic controls, shown above the
/// navigation bar (phone) or below the whole layout (desktop).
///
/// Hidden while nothing is playing. Tapping it opens Now Playing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlayerViewModel>();
    final state = vm.state;
    if (state == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push(AppRoutes.nowPlaying),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: vm.progress, minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  CoverImage(state.coverUrl, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                        Text(
                          state.artistNames.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous',
                    onPressed: () => runPlayerCommand(context, vm.previous),
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    tooltip: state.isPlaying ? 'Pause' : 'Play',
                    onPressed: () => runPlayerCommand(context, vm.togglePlayPause),
                    icon: Icon(
                      state.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: () => runPlayerCommand(context, vm.next),
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Runs a [PlayerViewModel] command and shows its error, if any.
Future<void> runPlayerCommand(
  BuildContext context,
  Future<String?> Function() command,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await command();
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}