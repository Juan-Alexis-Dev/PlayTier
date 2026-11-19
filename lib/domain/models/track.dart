/// A track of the main playlist (or any list shown in the app).
///
/// Immutable. Artists are referenced by id; their data lives in [Artist].
class Track {
  const Track({
    required this.id,
    required this.uri,
    required this.name,
    required this.artistIds,
    required this.albumId,
    required this.albumName,
    required this.duration,
    this.releaseDate,
    this.addedAt,
    this.coverUrl,
  });

  /// Spotify track id.
  final String id;

  /// Spotify URI (`spotify:track:<id>`), used for playback and playlists.
  final String uri;

  final String name;

  /// Spotify artist ids, in the order Spotify returns them.
  final List<String> artistIds;

  final String albumId;
  final String albumName;
  final Duration duration;

  /// Release date as Spotify returns it: `YYYY`, `YYYY-MM` or `YYYY-MM-DD`.
  final String? releaseDate;

  /// When the track was added to the playlist (null for very old items).
  final DateTime? addedAt;

  /// Album cover URL (largest image), if any.
  final String? coverUrl;

  /// Release year parsed from [releaseDate], or null if unknown.
  int? get releaseYear {
    final date = releaseDate;
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  Track copyWith({
    String? id,
    String? uri,
    String? name,
    List<String>? artistIds,
    String? albumId,
    String? albumName,
    Duration? duration,
    String? releaseDate,
    DateTime? addedAt,
    String? coverUrl,
  }) {
    return Track(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      name: name ?? this.name,
      artistIds: artistIds ?? this.artistIds,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      duration: duration ?? this.duration,
      releaseDate: releaseDate ?? this.releaseDate,
      addedAt: addedAt ?? this.addedAt,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          other.id == id &&
          other.uri == uri &&
          other.name == name &&
          _listEquals(other.artistIds, artistIds) &&
          other.albumId == albumId &&
          other.albumName == albumName &&
          other.duration == duration &&
          other.releaseDate == releaseDate &&
          other.addedAt == addedAt &&
          other.coverUrl == coverUrl;

  @override
  int get hashCode => Object.hash(
        id,
        uri,
        name,
        Object.hashAll(artistIds),
        albumId,
        albumName,
        duration,
        releaseDate,
        addedAt,
        coverUrl,
      );

  @override
  String toString() => 'Track($id, $name)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}