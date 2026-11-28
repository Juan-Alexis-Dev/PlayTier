import 'package:material_ui/material_ui.dart';

import '../../../domain/models/discover_mode.dart';

/// One Discover option: icon, title and description (FR-10).
///
/// Disabled when [onTap] is null; [comingSoon] replaces the description
/// with "Coming soon". Shows a spinner while [loading].
class DiscoverCard extends StatelessWidget {
  const DiscoverCard({
    super.key,
    required this.mode,
    required this.onTap,
    this.loading = false,
    this.comingSoon = false,
  });

  final DiscoverMode mode;
  final VoidCallback? onTap;
  final bool loading;
  final bool comingSoon;

  static IconData iconOf(DiscoverMode mode) => switch (mode) {
        DiscoverMode.fromArtists => Icons.person_search,
        DiscoverMode.fromGenres => Icons.category,
        DiscoverMode.youCouldLike => Icons.favorite_border,
        DiscoverMode.toTry => Icons.explore,
        DiscoverMode.custom => Icons.tune,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onTap != null;
    final foreground = enabled ? colors.onSurface : colors.onSurfaceVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                child: loading
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Icon(
                        iconOf(mode),
                        size: 28,
                        color: enabled ? colors.primary : foreground,
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                mode.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                comingSoon ? 'Coming soon' : mode.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}