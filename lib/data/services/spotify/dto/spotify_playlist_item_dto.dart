import 'spotify_artist_dto.dart';

/// One track of `GET /playlists/{id}/items`, with its `added_at`.
class SpotifyPlaylistItemDto {
  const SpotifyPlaylistItemDto({
    required this.id,
    required this.uri,
    required this.name,
    required this.durationMs,
    required this.albumId,
    required this.albumName,
    required this.artists,
    this.releaseDate,
    this.coverUrl,
    this.addedAt,
  });

  /// Parses one entry of the `items` array.
  ///
  /// Returns null for entries the app ignores: local files, episodes,
  /// unplayable tracks and removed tracks (`item: null`).
  static SpotifyPlaylistItemDto? tryParse(Map<String, dynamic> json) {
    if (json['is_local'] == true) return null;

    // `item` in the current API; `track` in older responses.
    final item = json['item'] ?? json['track'];
    if (item is! Map<String, dynamic>) return null;
    if (item['type'] != 'track') return null;
    if (item['is_local'] == true || item['is_playable'] == false) return null;

    final id = item['id'];
    if (id is! String) return null;

    final album = item['album'] as Map<String, dynamic>? ?? const {};
    final images = album['images'] as List<dynamic>? ?? const [];

    return SpotifyPlaylistItemDto(
      id: id,
      uri: item['uri'] as String? ?? 'spotify:track:$id',
      name: item['name'] as String? ?? '',
      durationMs: item['duration_ms'] as int? ?? 0,
      albumId: album['id'] as String? ?? '',
      albumName: album['name'] as String? ?? '',
      releaseDate: album['release_date'] as String?,
      coverUrl: images.isEmpty
          ? null
          : (images.first as Map<String, dynamic>)['url'] as String?,
      addedAt: DateTime.tryParse(json['added_at'] as String? ?? ''),
      artists: [
        for (final artist in item['artists'] as List<dynamic>? ?? const [])
          if (artist is Map<String, dynamic> && artist['id'] is String)
            SpotifyArtistDto(
              id: artist['id'] as String,
              name: artist['name'] as String? ?? '',
            ),
      ],
    );
  }

  final String id;
  final String uri;
  final String name;
  final int durationMs;
  final String albumId;
  final String albumName;
  final List<SpotifyArtistDto> artists;
  final String? releaseDate;
  final String? coverUrl;
  final DateTime? addedAt;
}