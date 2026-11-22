import '../models/filter_criteria.dart';
import '../models/track.dart';

/// Applies a [FilterCriteria] to a list of tracks (FR-5.2).

/// Values of the same type are combined with OR (Rock OR Pop) and different
/// types with AND ((Rock OR Pop) AND artist X). A type with no values is
/// ignored. Pure Dart, no I/O.
abstract final class FilterEngine {
  /// Returns the tracks of [tracks] that match [criteria], keeping their
  /// original order.
  ///
  /// - [genresByArtist]: artist id → genres. A track's genres are the union
  ///   of its artists' genres. Artists missing from the map have no genres.
  /// - [levels]: track id → like level. Tracks missing from the map are
  ///   level 1 (FR-3.1).
  ///
  /// When a year or date-added range is active, tracks without a release
  /// year or without `addedAt` do not match. Range bounds are inclusive;
  /// pass the end of the day as `addedTo` to include that whole day.
  static List<Track> apply(
    List<Track> tracks,
    FilterCriteria criteria, {
    Map<String, List<String>> genresByArtist = const {},
    Map<String, int> levels = const {},
  }) {
    if (criteria.isEmpty) return List.of(tracks);
    return tracks
        .where((t) => _matches(t, criteria, genresByArtist, levels))
        .toList();
  }

  static bool _matches(
    Track track,
    FilterCriteria c,
    Map<String, List<String>> genresByArtist,
    Map<String, int> levels,
  ) {
    if (c.genres.isNotEmpty &&
        !track.artistIds.any(
          (id) => (genresByArtist[id] ?? const []).any(c.genres.contains),
        )) {
      return false;
    }
    if (c.artistIds.isNotEmpty && !track.artistIds.any(c.artistIds.contains)) {
      return false;
    }
    if (c.albumIds.isNotEmpty && !c.albumIds.contains(track.albumId)) {
      return false;
    }
    if (c.levels.isNotEmpty && !c.levels.contains(levels[track.id] ?? 1)) {
      return false;
    }
    if (c.hasYearRange && !_inYearRange(track.releaseYear, c)) {
      return false;
    }
    if (c.hasAddedRange && !_inAddedRange(track.addedAt, c)) {
      return false;
    }
    return true;
  }

  static bool _inYearRange(int? year, FilterCriteria c) {
    if (year == null) return false;
    final from = c.yearFrom;
    final to = c.yearTo;
    return (from == null || year >= from) && (to == null || year <= to);
  }

  static bool _inAddedRange(DateTime? added, FilterCriteria c) {
    if (added == null) return false;
    final from = c.addedFrom;
    final to = c.addedTo;
    return (from == null || !added.isBefore(from)) &&
        (to == null || !added.isAfter(to));
  }
}