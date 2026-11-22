import 'package:material_ui/material_ui.dart';

import '../../../shared/widgets/cover_image.dart';

/// Cover, name and "N tracks · duration". Side by side on wide screens,
/// stacked and centered on narrow ones.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.name,
    required this.trackCount,
    required this.totalDuration,
    this.coverUrl,
  });

  final String name;
  final int trackCount;
  final Duration totalDuration;
  final String? coverUrl;

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
        final cover = CoverImage(
          coverUrl,
          size: wide ? 192 : 160,
          borderRadius: 8,
        );
        final texts = Column(
          crossAxisAlignment:
              wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text('Playlist', style: textTheme.labelLarge),
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