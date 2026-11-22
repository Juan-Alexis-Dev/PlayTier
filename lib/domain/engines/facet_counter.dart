import '../models/track.dart';

/// A filter value and how many tracks have it.
typedef FacetCount = ({String value, int count});

/// Counts genres, artists and albums in a list of tracks, ordered by
/// frequency (FR-5.3). Used by the filter lists and the Genres/Artists
/// pages. Pure Dart, no I/O.
///
/// Results are sorted by count (highest first); ties are sorted by name,
/// ignoring case. Each track counts at most once per value.
abstract final class FacetCounter {
  /// Genres of [tracks]. A track's genres are the union of its artists'
  /// genres in [genresByArtist] (artist id → genres).
  static List<FacetCount> genres(
    List<Track> tracks,
    Map<String, List<String>> genresByArtist,
  ) {
    final counts = <String, int>{};
    for (final track in tracks) {
      final trackGenres = {
        for (final id in track.artistIds) ...?genresByArtist[id],
      };
      _addAll(counts, trackGenres);
    }
    return _rank(counts, (genre) => genre);
  }

  /// Artist ids of [tracks], featured artists included. [artistNames]
  /// (artist id → name) is only used to break ties; unknown ids use the id.
  static List<FacetCount> artists(
    List<Track> tracks, {
    Map<String, String> artistNames = const {},
  }) {
    final counts = <String, int>{};
    for (final track in tracks) {
      _addAll(counts, track.artistIds.toSet());
    }
    return _rank(counts, (id) => artistNames[id] ?? id);
  }

  /// Album ids of [tracks].
  static List<FacetCount> albums(List<Track> tracks) {
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final track in tracks) {
      _addAll(counts, {track.albumId});
      names[track.albumId] = track.albumName;
    }
    return _rank(counts, (id) => names[id] ?? id);
  }

  static void _addAll(Map<String, int> counts, Set<String> values) {
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
  }

  static List<FacetCount> _rank(
    Map<String, int> counts,
    String Function(String value) label,
  ) {
    final result = [
      for (final MapEntry(:key, :value) in counts.entries)
        (value: key, count: value),
    ];
    result.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return label(a.value).toLowerCase().compareTo(label(b.value).toLowerCase());
    });
    return result;
  }
}