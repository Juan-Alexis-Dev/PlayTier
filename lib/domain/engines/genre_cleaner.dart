/// A raw genre or tag from an external source and its weight
/// (Last.fm 0–100, MusicBrainz votes, 0 when the source has none).
typedef RawGenre = ({String name, int count});

/// Turns raw genres/tags into clean genre names (FR-2.5). Pure Dart, no I/O.
///
/// - lower-case, trimmed, inner spaces collapsed, duplicates removed;
/// - drops tags that are not genres ([ignoredTags], the artist's own name);
/// - drops tags below [minCount];
/// - keeps the [limit] highest-weighted (ties keep their original order).
abstract final class GenreCleaner {
  /// Common Last.fm tags that describe the listener, not the music.
  static const ignoredTags = {
    'seen live',
    'favorites',
    'favourites',
    'favorite',
    'favourite',
    'my favorite',
    'albums i own',
    'love',
    'awesome',
    'beautiful',
    'male vocalists',
    'female vocalists',
    'male vocalist',
    'female vocalist',
    'under 2000 listeners',
  };

  static List<String> clean(
    List<RawGenre> raw, {
    required String artistName,
    int minCount = 0,
    int? limit = 5,
  }) {
    final artist = _normalize(artistName);
    final indexed = [
      for (final (index, genre) in raw.indexed)
        (index: index, name: _normalize(genre.name), count: genre.count),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.index.compareTo(b.index);
      });

    final result = <String>[];
    for (final genre in indexed) {
      if (limit != null && result.length >= limit) break;
      if (genre.name.isEmpty ||
          genre.count < minCount ||
          genre.name == artist ||
          ignoredTags.contains(genre.name) ||
          result.contains(genre.name)) {
        continue;
      }
      result.add(genre.name);
    }
    return result;
  }

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}