import 'package:material_ui/material_ui.dart';

import '../../domain/models/like_level.dart';

/// Five stars to show and set a like level (FR-12.3).
///
/// Tapping star N sets level N; the minimum is 1 (tap the first star).
/// A null [onChanged] shows the stars disabled.
class LevelStars extends StatelessWidget {
  const LevelStars({
    super.key,
    required this.level,
    this.onChanged,
    this.size = 32,
  });

  final int level;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onChanged != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = LikeLevel.min; n <= LikeLevel.max; n++)
          IconButton(
            tooltip: 'Level $n',
            iconSize: size,
            onPressed: enabled ? () => onChanged!(n) : null,
            icon: Icon(
              n <= level ? Icons.star : Icons.star_border,
              color: enabled && n <= level ? colors.primary : null,
            ),
          ),
      ],
    );
  }
}