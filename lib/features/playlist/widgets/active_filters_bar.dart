import 'package:material_ui/material_ui.dart';

import '../../../domain/models/filter_criteria.dart';
import '../../../domain/models/sort_option.dart';
import 'sort_sheet.dart';

/// Shown under the action row while filters or a custom order are active:
/// "N of M tracks", plus chips to edit or clear them.
class ActiveFiltersBar extends StatelessWidget {
  const ActiveFiltersBar({
    super.key,
    required this.criteria,
    required this.sort,
    required this.shown,
    required this.total,
    required this.onEditFilters,
    required this.onClearFilters,
    required this.onClearSort,
  });

  final FilterCriteria criteria;
  final SortOption? sort;
  final int shown;
  final int total;
  final VoidCallback onEditFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onClearSort;

  @override
  Widget build(BuildContext context) {
    final sort = this.sort;
    final count = criteria.activeCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$shown of $total tracks'),
          if (criteria.isNotEmpty)
            InputChip(
              avatar: const Icon(Icons.filter_list, size: 18),
              label: Text(count == 1 ? '1 filter' : '$count filters'),
              onPressed: onEditFilters,
              onDeleted: onClearFilters,
              deleteButtonTooltipMessage: 'Clear filters',
            ),
          if (sort != null)
            InputChip(
              avatar: Icon(
                sort.isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
              ),
              label: Text(SortSheet.labels[sort.field]!),
              onDeleted: onClearSort,
              deleteButtonTooltipMessage: 'Playlist order',
            ),
        ],
      ),
    );
  }
}