import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/cover_image.dart';
import 'player_view_model.dart';

/// Bar with the current track and basic controls, shown above the
/// navigation bar (phone) or below the whole layout (desktop).
///
/// Hidden while nothing is playing. [onTap] opens Now Playing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.onTap});

  final VoidCallback? onTap;

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
        onTap: onTap,
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
                    onPressed: () => _run(context, vm.previous),
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    tooltip: state.isPlaying ? 'Pause' : 'Play',
                    onPressed: () => _run(context, vm.togglePlayPause),
                    icon: Icon(
                      state.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: () => _run(context, vm.next),
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

  Future<void> _run(
    BuildContext context,
    Future<String?> Function() command,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await command();
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}