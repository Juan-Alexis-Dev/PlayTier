import '../models/sort_option.dart';
import '../models/track.dart';

/// Sorts a list of tracks by a [SortOption] (FR-5.4). Pure Dart, no I/O.
abstract final class SortEngine {
  /// Returns a new list with [tracks] sorted by [option].
  ///
  /// - [artistNames]: artist id → name, used by [SortField.artist] (the
  ///   first artist of each track). Unknown ids sort as an empty name.
  /// - [levels]: track id → like level. Missing tracks are level 1 (FR-3.1).
  ///
  /// Text is compared ignoring case. The sort is stable: tracks with equal
  /// values keep their original order in both directions. Tracks without
  /// `addedAt` always go last when sorting by date added.
  static List<Track> sort(
    List<Track> tracks,
    SortOption option, {
    Map<String, String> artistNames = const {},
    Map<String, int> levels = const {},
  }) {
    final sign = option.isAscending ? 1 : -1;
    final indexed = tracks.indexed.toList();

    indexed.sort((a, b) {
      final result = _compare(a.$2, b.$2, option.field, sign, artistNames, levels);
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });

    return [for (final (_, track) in indexed) track];
  }

  /// Compares two tracks by [field], already applying the direction [sign].
  static int _compare(
    Track a,
    Track b,
    SortField field,
    int sign,
    Map<String, String> artistNames,
    Map<String, int> levels,
  ) {
    switch (field) {
      case SortField.dateAdded:
        final x = a.addedAt;
        final y = b.addedAt;
        if (x == null || y == null) {
          // Nulls last, regardless of direction.
          if (x == null && y == null) return 0;
          return x == null ? 1 : -1;
        }
        return sign * x.compareTo(y);
      case SortField.title:
        return sign * _compareText(a.name, b.name);
      case SortField.artist:
        return sign *
            _compareText(_firstArtist(a, artistNames), _firstArtist(b, artistNames));
      case SortField.album:
        return sign * _compareText(a.albumName, b.albumName);
      case SortField.duration:
        return sign * a.duration.compareTo(b.duration);
      case SortField.likeLevel:
        return sign * (levels[a.id] ?? 1).compareTo(levels[b.id] ?? 1);
    }
  }

  static String _firstArtist(Track track, Map<String, String> artistNames) =>
      track.artistIds.isEmpty ? '' : artistNames[track.artistIds.first] ?? '';

  static int _compareText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}