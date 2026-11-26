import 'package:material_ui/material_ui.dart';

import '../../../domain/models/like_level.dart';
import '../../../domain/models/track.dart';
import '../../../shared/widgets/cover_image.dart';
import '../../../shared/widgets/level_stars.dart';

/// Bottom sheet to set the like level of a track without playing it.
///
/// Tapping a star closes the sheet with that level. A null [level] means
/// the track is not in the main playlist: the stars are disabled.
class LevelSheet extends StatelessWidget {
  const LevelSheet({
    super.key,
    required this.track,
    required this.artists,
    required this.level,
  });

  final Track track;
  final String artists;
  final int? level;

  /// Returns the chosen level, or null if dismissed.
  static Future<int?> show(
    BuildContext context, {
    required Track track,
    required String artists,
    required int? level,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => LevelSheet(track: track, artists: artists, level: level),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final level = this.level;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CoverImage(track.coverUrl, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        artists,
                        style: text.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LevelStars(
              level: level ?? LikeLevel.min,
              onChanged:
                  level == null ? null : (n) => Navigator.of(context).pop(n),
            ),
            if (level == null)
              Text(
                'Not in your main playlist, so it has no level.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}