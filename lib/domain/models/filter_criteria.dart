/// Filters selected by the user for a list of tracks (FR-5.1, FR-5.2).
///
/// Immutable. Values of the same type are combined with OR and different
/// types with AND; an empty set or a null bound means "no filter" for that
/// type. The logic itself lives in `FilterEngine`.
class FilterCriteria {
  FilterCriteria({
    Set<String> genres = const {},
    Set<String> artistIds = const {},
    Set<String> albumIds = const {},
    Set<int> levels = const {},
    this.yearFrom,
    this.yearTo,
    this.addedFrom,
    this.addedTo,
  })  : assert(levels.every((l) => l >= 1 && l <= 5), 'levels must be 1–5'),
        assert(
          yearFrom == null || yearTo == null || yearFrom <= yearTo,
          'yearFrom must be <= yearTo',
        ),
        assert(
          addedFrom == null || addedTo == null || !addedFrom.isAfter(addedTo),
          'addedFrom must be <= addedTo',
        ),
        genres = Set.unmodifiable(genres),
        artistIds = Set.unmodifiable(artistIds),
        albumIds = Set.unmodifiable(albumIds),
        levels = Set.unmodifiable(levels);

  /// No filters: every track passes.
  static final FilterCriteria empty = FilterCriteria();

  /// Genre names.
  final Set<String> genres;

  /// Spotify artist ids (featured artists included).
  final Set<String> artistIds;

  /// Spotify album ids.
  final Set<String> albumIds;

  /// Like levels, 1–5.
  final Set<int> levels;

  /// Release year range, inclusive. A null bound is open.
  final int? yearFrom;
  final int? yearTo;

  /// Date-added range, inclusive. A null bound is open.
  final DateTime? addedFrom;
  final DateTime? addedTo;

  bool get hasYearRange => yearFrom != null || yearTo != null;
  bool get hasAddedRange => addedFrom != null || addedTo != null;

  /// Number of filter types in use (used for badges in the UI).
  int get activeCount => [
        genres.isNotEmpty,
        artistIds.isNotEmpty,
        albumIds.isNotEmpty,
        levels.isNotEmpty,
        hasYearRange,
        hasAddedRange,
      ].where((active) => active).length;

  bool get isEmpty => activeCount == 0;
  bool get isNotEmpty => !isEmpty;

  /// Copy with new value sets. Ranges are changed with [withYearRange] and
  /// [withAddedRange], because they need to accept null to clear a bound.
  FilterCriteria copyWith({
    Set<String>? genres,
    Set<String>? artistIds,
    Set<String>? albumIds,
    Set<int>? levels,
  }) {
    return FilterCriteria(
      genres: genres ?? this.genres,
      artistIds: artistIds ?? this.artistIds,
      albumIds: albumIds ?? this.albumIds,
      levels: levels ?? this.levels,
      yearFrom: yearFrom,
      yearTo: yearTo,
      addedFrom: addedFrom,
      addedTo: addedTo,
    );
  }

  /// Copy with a new release year range. Pass nulls to clear it.
  FilterCriteria withYearRange(int? from, int? to) {
    return FilterCriteria(
      genres: genres,
      artistIds: artistIds,
      albumIds: albumIds,
      levels: levels,
      yearFrom: from,
      yearTo: to,
      addedFrom: addedFrom,
      addedTo: addedTo,
    );
  }

  /// Copy with a new date-added range. Pass nulls to clear it.
  FilterCriteria withAddedRange(DateTime? from, DateTime? to) {
    return FilterCriteria(
      genres: genres,
      artistIds: artistIds,
      albumIds: albumIds,
      levels: levels,
      yearFrom: yearFrom,
      yearTo: yearTo,
      addedFrom: from,
      addedTo: to,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterCriteria &&
          _setEquals(other.genres, genres) &&
          _setEquals(other.artistIds, artistIds) &&
          _setEquals(other.albumIds, albumIds) &&
          _setEquals(other.levels, levels) &&
          other.yearFrom == yearFrom &&
          other.yearTo == yearTo &&
          other.addedFrom == addedFrom &&
          other.addedTo == addedTo;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(genres),
        Object.hashAllUnordered(artistIds),
        Object.hashAllUnordered(albumIds),
        Object.hashAllUnordered(levels),
        yearFrom,
        yearTo,
        addedFrom,
        addedTo,
      );

  @override
  String toString() => 'FilterCriteria(genres: $genres, artists: $artistIds, '
      'albums: $albumIds, levels: $levels, years: $yearFrom–$yearTo, '
      'added: $addedFrom–$addedTo)';
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);