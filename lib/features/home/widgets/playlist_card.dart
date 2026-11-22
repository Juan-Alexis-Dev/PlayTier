import 'package:flutter/material.dart';

/// Square artwork with a title and subtitle below. Used for the large
/// Main/Liked cards and the "Your playlists" grid.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.artwork,
    required this.title,
    this.subtitle,
    this.onTap,
    this.large = false,
  });

  /// Fills a square; usually a `CoverImage` or an icon on a color.
  final Widget artwork;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Bigger text for the Main/Liked cards.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final text = subtitle;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: artwork,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: large ? textTheme.titleLarge : textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (text != null)
                Text(
                  text,
                  style: textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}