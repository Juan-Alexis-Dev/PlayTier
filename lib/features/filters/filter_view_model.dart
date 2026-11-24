import 'package:flutter/foundation.dart';

import '../../domain/engines/facet_counter.dart';
import '../../domain/engines/filter_engine.dart';
import '../../domain/models/filter_criteria.dart';
import '../../domain/models/track.dart';

/// State of the filter sheet: builds a [FilterCriteria] (FR-5.1, FR-5.2).
///
/// Works on the tracks it receives (no repositories). Value lists are
/// counted once, from the full list, and ordered by frequency (FR-5.3).
/// [matchCount] updates live while the user picks values.
class FilterViewModel extends ChangeNotifier {
  FilterViewModel({
    required List<Track> tracks,
    required Map<String, List<String>> genresByArtist,
    required Map<String, String> artistNames,
    required this._levels,
    FilterCriteria? initial,
  })  : _tracks = tracks,
        _genresByArtist = genresByArtist,
        _criteria = initial ?? FilterCriteria.empty,
        artistNames = artistNames,
        albumNames = {for (final t in tracks) t.albumId: t.albumName},
        genres = FacetCounter.genres(tracks, genresByArtist),
        artists = FacetCounter.artists(tracks, artistNames: artistNames),
        albums = FacetCounter.albums(tracks) {
    final years = tracks.map((t) => t.releaseYear).nonNulls;
    minYear = years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b);
    maxYear = years.isEmpty ? null : years.reduce((a, b) => a > b ? a : b);
    _count();
  }

  final List<Track> _tracks;
  final Map<String, List<String>> _genresByArtist;
  final Map<String, int> _levels;
  FilterCriteria _criteria;
  int _matchCount = 0;

  /// Values with their track counts, most frequent first.
  final List<FacetCount> genres;
  final List<FacetCount> artists;
  final List<FacetCount> albums;

  /// Labels for artist and album ids.
  final Map<String, String> artistNames;
  final Map<String, String> albumNames;

  /// Release year bounds of the list (null if no track has a year).
  late final int? minYear;
  late final int? maxYear;

  FilterCriteria get criteria => _criteria;

  /// Tracks that pass the current criteria.
  int get matchCount => _matchCount;

  void toggleGenre(String genre) =>
      _update(_criteria.copyWith(genres: _toggle(_criteria.genres, genre)));

  void toggleArtist(String id) =>
      _update(_criteria.copyWith(artistIds: _toggle(_criteria.artistIds, id)));

  void toggleAlbum(String id) =>
      _update(_criteria.copyWith(albumIds: _toggle(_criteria.albumIds, id)));

  void toggleLevel(int level) =>
      _update(_criteria.copyWith(levels: _toggle(_criteria.levels, level)));

  /// Selecting the whole range of the list clears the year filter.
  void setYearRange(int from, int to) {
    final whole = from == minYear && to == maxYear;
    _update(_criteria.withYearRange(whole ? null : from, whole ? null : to));
  }

  /// [to] is taken as the end of that day, so the whole day is included.
  void setAddedRange(DateTime? from, DateTime? to) {
    final start = from == null ? null : DateTime(from.year, from.month, from.day);
    final end = to == null
        ? null
        : DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    _update(_criteria.withAddedRange(start, end));
  }

  void clear() => _update(FilterCriteria.empty);

  void _update(FilterCriteria criteria) {
    _criteria = criteria;
    _count();
    notifyListeners();
  }

  void _count() {
    _matchCount = FilterEngine.apply(
      _tracks,
      _criteria,
      genresByArtist: _genresByArtist,
      levels: _levels,
    ).length;
  }

  static Set<T> _toggle<T>(Set<T> values, T value) =>
      values.contains(value) ? ({...values}..remove(value)) : {...values, value};
}