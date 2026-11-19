/// An artist with its genres.
///
/// Genres come from Spotify, or from Last.fm/MusicBrainz when Spotify
/// has none (see `GenreRepository`). Empty until enrichment runs.
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.genres = const [],
  });

  /// Spotify artist id.
  final String id;

  final String name;

  /// Lower-case genre names.
  final List<String> genres;

  Artist copyWith({
    String? id,
    String? name,
    List<String>? genres,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      genres: genres ?? this.genres,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artist &&
          other.id == id &&
          other.name == name &&
          _listEquals(other.genres, genres);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(genres));

  @override
  String toString() => 'Artist($id, $name)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}