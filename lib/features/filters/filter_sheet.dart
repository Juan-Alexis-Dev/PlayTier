import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../domain/engines/facet_counter.dart';
import '../../domain/models/filter_criteria.dart';
import 'filter_view_model.dart';

/// Multi-filter panel (FR-5). Open it with [FilterSheet.show]; it returns
/// the chosen [FilterCriteria], or null if the user closed it.
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key});

  /// Shows the sheet for [viewModel] and returns the applied criteria.
  static Future<FilterCriteria?> show(
    BuildContext context,
    FilterViewModel Function() viewModel,
  ) {
    return showModalBottomSheet<FilterCriteria>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ChangeNotifierProvider(
        create: (_) => viewModel(),
        child: const FilterSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FilterViewModel>();
    final criteria = vm.criteria;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Filters', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: criteria.isEmpty ? null : vm.clear,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (vm.genres.isNotEmpty)
                  _Section(
                    title: 'Genres',
                    child: _FacetChips(
                      facets: vm.genres,
                      selected: criteria.genres,
                      label: (genre) => genre,
                      onToggle: vm.toggleGenre,
                    ),
                  ),
                if (vm.artists.isNotEmpty)
                  _Section(
                    title: 'Artists',
                    child: _FacetChips(
                      facets: vm.artists,
                      selected: criteria.artistIds,
                      label: (id) => vm.artistNames[id] ?? id,
                      onToggle: vm.toggleArtist,
                    ),
                  ),
                if (vm.albums.isNotEmpty)
                  _Section(
                    title: 'Albums',
                    child: _FacetChips(
                      facets: vm.albums,
                      selected: criteria.albumIds,
                      label: (id) => vm.albumNames[id] ?? id,
                      onToggle: vm.toggleAlbum,
                    ),
                  ),
                _Section(
                  title: 'Like level',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (var level = 1; level <= 5; level++)
                        FilterChip(
                          label: Text('$level'),
                          avatar: const Icon(Icons.star, size: 18),
                          selected: criteria.levels.contains(level),
                          onSelected: (_) => vm.toggleLevel(level),
                        ),
                    ],
                  ),
                ),
                if (vm.minYear != null && vm.minYear! < vm.maxYear!)
                  _Section(
                    title: 'Release year',
                    child: _YearRange(vm: vm),
                  ),
                _Section(
                  title: 'Date added',
                  child: _AddedRange(vm: vm),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: vm.matchCount == 0
                      ? null
                      : () => Navigator.pop(context, criteria),
                  child: Text(
                    vm.matchCount == 0
                        ? 'No tracks match'
                        : 'Show ${vm.matchCount} tracks',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Chips for one filter type. Shows the most frequent values first and
/// hides the rest behind "Show all".
class _FacetChips extends StatefulWidget {
  const _FacetChips({
    required this.facets,
    required this.selected,
    required this.label,
    required this.onToggle,
  });

  final List<FacetCount> facets;
  final Set<String> selected;
  final String Function(String value) label;
  final void Function(String value) onToggle;

  @override
  State<_FacetChips> createState() => _FacetChipsState();
}

class _FacetChipsState extends State<_FacetChips> {
  static const _collapsedCount = 15;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final facets = widget.facets;
    final canCollapse = facets.length > _collapsedCount;
    final visible = _expanded || !canCollapse
        ? facets
        : [
            ...facets.take(_collapsedCount),
            // Keep selected values visible even when collapsed.
            ...facets.skip(_collapsedCount)
                .where((f) => widget.selected.contains(f.value)),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final facet in visible)
              FilterChip(
                label: Text('${widget.label(facet.value)} (${facet.count})'),
                selected: widget.selected.contains(facet.value),
                onSelected: (_) => widget.onToggle(facet.value),
              ),
          ],
        ),
        if (canCollapse)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Show all (${facets.length})'),
          ),
      ],
    );
  }
}

class _YearRange extends StatelessWidget {
  const _YearRange({required this.vm});

  final FilterViewModel vm;

  @override
  Widget build(BuildContext context) {
    final min = vm.minYear!;
    final max = vm.maxYear!;
    final from = vm.criteria.yearFrom ?? min;
    final to = vm.criteria.yearTo ?? max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(vm.criteria.hasYearRange ? '$from – $to' : 'Any year'),
        RangeSlider(
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          values: RangeValues(from.toDouble(), to.toDouble()),
          labels: RangeLabels('$from', '$to'),
          onChanged: (values) =>
              vm.setYearRange(values.start.round(), values.end.round()),
        ),
      ],
    );
  }
}

class _AddedRange extends StatelessWidget {
  const _AddedRange({required this.vm});

  final FilterViewModel vm;

  static String _format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final from = vm.criteria.addedFrom;
    final to = vm.criteria.addedTo;

    return Row(
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text(
            from == null || to == null
                ? 'Any time'
                : '${_format(from)} – ${_format(to)}',
          ),
          onPressed: () async {
            final now = DateTime.now();
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2008),
              lastDate: now,
              // Date-only values: `to` is stored as the end of the day,
              // which can be later than `lastDate`.
              initialDateRange: from == null || to == null
                  ? null
                  : DateTimeRange(
                      start: DateTime(from.year, from.month, from.day),
                      end: DateTime(to.year, to.month, to.day),
                    ),
            );
            if (range != null) vm.setAddedRange(range.start, range.end);
          },
        ),
        if (vm.criteria.hasAddedRange)
          IconButton(
            tooltip: 'Clear date added',
            icon: const Icon(Icons.close),
            onPressed: () => vm.setAddedRange(null, null),
          ),
      ],
    );
  }
}