/// Kind of playlist shown in Home, Genres or Artists.
enum PlaylistType {
  /// The user's main Spotify playlist.
  main,
  /// Virtual playlist with tracks of level 2–5.
  liked,
  /// Virtual playlist of one genre.
  genre,
  /// Virtual playlist of one artist.
  artist,
  /// Real Spotify playlist created from the app.
  permanent,
}

/// Lightweight playlist data for cards and headers (no tracks).
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.type,
    this.coverUrl,
  });

  /// Spotify playlist id for [PlaylistType.main] and
  /// [PlaylistType.permanent]; genre name or artist id for virtual ones.
  final String id;

  final String name;
  final int trackCount;
  final PlaylistType type;

  /// Cover URL, if any. Virtual playlists use a cover mosaic instead.
  final String? coverUrl;

  /// True for playlists that exist only inside the app.
  bool get isVirtual =>
      type == PlaylistType.liked ||
      type == PlaylistType.genre ||
      type == PlaylistType.artist;

  PlaylistSummary copyWith({
    String? id,
    String? name,
    int? trackCount,
    PlaylistType? type,
    String? coverUrl,
  }) {
    return PlaylistSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      trackCount: trackCount ?? this.trackCount,
      type: type ?? this.type,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistSummary &&
          other.id == id &&
          other.name == name &&
          other.trackCount == trackCount &&
          other.type == type &&
          other.coverUrl == coverUrl;

  @override
  int get hashCode => Object.hash(id, name, trackCount, type, coverUrl);

  @override
  String toString() => 'PlaylistSummary(${type.name}, $id, $name)';
}