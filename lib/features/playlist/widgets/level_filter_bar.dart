import 'package:material_ui/material_ui.dart';

/// Level chips 2–5 of the Liked page (FR-7.2). They only show or hide
/// tracks; all are selected by default.
class LevelFilterBar extends StatelessWidget {
  const LevelFilterBar({
    super.key,
    required this.levels,
    required this.shown,
    required this.onToggle,
  });

  /// Levels offered, in order (2–5).
  final Iterable<int> levels;

  /// Levels currently shown.
  final Set<int> shown;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final level in levels)
            FilterChip(
              avatar: const Icon(Icons.star, size: 18),
              label: Text('$level'),
              tooltip: 'Level $level',
              showCheckmark: false,
              selected: shown.contains(level),
              onSelected: (_) => onToggle(level),
            ),
        ],
      ),
    );
  }
}