import 'package:material_ui/material_ui.dart';

import '../../../domain/models/track.dart';
import '../../../shared/widgets/cover_image.dart';

/// One row of the track list: cover, name, artists, like level badge and
/// duration.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.artists,
    this.level,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.onRemove,
    this.action,
  });

  final Track track;

  /// Artist names already joined ("A, B").
  final String artists;

  /// Like level; a "★N" badge is shown before the duration for 2–5.
  final int? level;

  final VoidCallback? onTap;

  /// Opens the track options (e.g. set the level) on phones.
  final VoidCallback? onLongPress;

  /// Shows a "More options" button after the duration (desktop).
  final VoidCallback? onMore;

  /// Shows a remove button next to the duration (preview screen).
  final VoidCallback? onRemove;

  /// Extra widget after the duration (e.g. the "Add" button in Search).
  final Widget? action;

  static String _formatDuration(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final level = this.level;

    return ListTile(
      leading: CoverImage(track.coverUrl),
      title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (level != null && level >= 2) ...[
            _LevelBadge(level),
            const SizedBox(width: 12),
          ],
          Text(_formatDuration(track.duration)),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onRemove,
            ),
          if (onMore != null)
            IconButton(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert),
              onPressed: onMore,
            ),
          ?action,
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// "★3": the like level of a liked track.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge(this.level);

  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Level $level',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 16, color: colors.primary),
          const SizedBox(width: 2),
          Text(
            '$level',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: colors.primary),
          ),
        ],
      ),
    );
  }
}