import 'package:material_ui/material_ui.dart';

import '../../../domain/models/sort_option.dart';

/// "Sort by" menu (FR-5.4). Tapping the selected field again reverses the
/// direction. A null option means the playlist's own order.
class SortSheet extends StatelessWidget {
  const SortSheet({super.key, required this.current, required this.onSelected});

  final SortOption? current;
  final ValueChanged<SortOption?> onSelected;

  static Future<void> show(
    BuildContext context, {
    required SortOption? current,
    required ValueChanged<SortOption?> onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SortSheet(current: current, onSelected: onSelected),
    );
  }

  /// Display name of each field (also used by `ActiveFiltersBar`).
  static const labels = {
    SortField.dateAdded: 'Date added',
    SortField.title: 'Title',
    SortField.artist: 'Artist',
    SortField.album: 'Album',
    SortField.duration: 'Duration',
    SortField.likeLevel: 'Like level',
  };

  /// First direction when a field is picked: newest and highest first.
  static SortDirection _firstDirection(SortField field) =>
      field == SortField.dateAdded || field == SortField.likeLevel
          ? SortDirection.descending
          : SortDirection.ascending;

  void _select(BuildContext context, SortOption? option) {
    onSelected(option);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final current = this.current;

    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Sort by', style: Theme.of(context).textTheme.titleLarge),
        ),
        ListTile(
          title: const Text('Playlist order'),
          trailing: current == null ? const Icon(Icons.check) : null,
          selected: current == null,
          onTap: () => _select(context, null),
        ),
        for (final field in SortField.values)
          ListTile(
            title: Text(labels[field]!),
            selected: current?.field == field,
            trailing: current?.field == field
                ? Icon(
                    current!.isAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  )
                : null,
            onTap: () => _select(
              context,
              current?.field == field
                  ? current!.reversed
                  : SortOption(field, _firstDirection(field)),
            ),
          ),
      ],
    );
  }
}