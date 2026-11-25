import '../models/filter_criteria.dart';

/// Builds a provisional, editable playlist name from the active filters
/// (FR-8.1), e.g. `Rock + Pop · Artist X · 1990–1999`. Pure Dart, no I/O.
///
/// Rules:
/// - One part per filter type, in this order: genres, artists, albums,
///   levels, release year, date added. Parts are joined with ` · `.
/// - Ranges: `1990–1999`, `From 1990`, `Until 1999`; dates as
///   `Added 2025-01-05 – 2025-02-10`, `Added since …`, `Added until …`.
/// - Values of one type are joined with ` + `, in the order they were
///   selected; after [maxValues] the rest become `+ N more`.
/// - Genres are shown in title case; unknown artist/album ids are skipped.
/// - The result is at most [maxLength] characters (ends with `…`).
/// - No filters (or nothing to show) gives [fallback].
abstract final class PlaylistNameGenerator {
  static const fallback = 'New playlist';
  static const maxValues = 2;

  /// Spotify accepts longer names, but short ones fit the UI.
  static const maxLength = 100;

  static String generate(
    FilterCriteria criteria, {
    Map<String, String> artistNames = const {},
    Map<String, String> albumNames = const {},
  }) {
    final parts = [
      _join(criteria.genres.map(_titleCase)),
      _join(criteria.artistIds.map((id) => artistNames[id]).nonNulls),
      _join(criteria.albumIds.map((id) => albumNames[id]).nonNulls),
      _levels(criteria.levels),
      _range(criteria.yearFrom?.toString(), criteria.yearTo?.toString()),
      _added(criteria),
    ].nonNulls.toList();

    if (parts.isEmpty) return fallback;
    final name = parts.join(' · ');
    return name.length <= maxLength
        ? name
        : '${name.substring(0, maxLength - 1).trimRight()}…';
  }

  static String? _join(Iterable<String> values) {
    final list = values.where((v) => v.trim().isNotEmpty).toList();
    if (list.isEmpty) return null;
    final shown = list.take(maxValues).join(' + ');
    final rest = list.length - maxValues;
    return rest > 0 ? '$shown + $rest more' : shown;
  }

  static String? _levels(Set<int> levels) {
    if (levels.isEmpty) return null;
    final sorted = levels.toList()..sort();
    return sorted.length == 1
        ? 'Level ${sorted.single}'
        : 'Levels ${sorted.join(', ')}';
  }

  /// `1990–1999`, `From 1990`, `Until 1999`, or `2005` when both are equal.
  static String? _range(String? from, String? to) {
    if (from == null && to == null) return null;
    if (from == null) return 'Until $to';
    if (to == null) return 'From $from';
    return from == to ? from : '$from–$to';
  }

  static String? _added(FilterCriteria c) {
    final from = _date(c.addedFrom);
    final to = _date(c.addedTo);
    if (from == null && to == null) return null;
    if (to == null) return 'Added since $from';
    if (from == null) return 'Added until $to';
    return from == to ? 'Added $from' : 'Added $from – $to';
  }

  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static String _titleCase(String text) => text
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}