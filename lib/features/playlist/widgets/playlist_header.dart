import 'package:material_ui/material_ui.dart';

import '../../../shared/widgets/cover_image.dart';
import '../../../shared/widgets/cover_mosaic.dart';

/// Cover, name and "N tracks · duration". Side by side on wide screens,
/// stacked and centered on narrow ones. With [coverUrls] the cover is a
/// mosaic (genre and artist playlists).
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.name,
    required this.trackCount,
    required this.totalDuration,
    this.coverUrl,
    this.coverUrls = const [],
    this.label = 'Playlist',
  });

  final String name;
  final int trackCount;
  final Duration totalDuration;
  final String? coverUrl;
  final List<String> coverUrls;

  /// Small text above the name ("Playlist", "Genre", "Artist").
  final String label;

  static String _formatTotal(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return hours > 0 ? '$hours h $minutes min' : '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitle = '$trackCount tracks · ${_formatTotal(totalDuration)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final size = wide ? 192.0 : 160.0;
        final cover = coverUrls.isNotEmpty
            ? CoverMosaic(coverUrls, size: size)
            : CoverImage(coverUrl, size: size, borderRadius: 8);
        final texts = Column(
          crossAxisAlignment:
              wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text(label, style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              name,
              style: textTheme.headlineMedium,
              textAlign: wide ? TextAlign.start : TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: textTheme.bodyMedium),
          ],
        );

        return Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    cover,
                    const SizedBox(width: 24),
                    Expanded(child: texts),
                  ],
                )
              : Column(
                  children: [cover, const SizedBox(height: 16), texts],
                ),
        );
      },
    );
  }
}