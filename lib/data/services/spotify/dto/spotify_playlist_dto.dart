/// Simplified playlist object from `GET /me/playlists`.
class SpotifyPlaylistDto {
  const SpotifyPlaylistDto({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.trackCount,
    this.imageUrl,
  });

  factory SpotifyPlaylistDto.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as List<dynamic>? ?? const [];
    // Newer API responses use `items`, older ones `tracks`.
    final counts = (json['items'] ?? json['tracks']) as Map<String, dynamic>?;
    final owner = json['owner'] as Map<String, dynamic>?;

    return SpotifyPlaylistDto(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      ownerId: owner?['id'] as String? ?? '',
      trackCount: counts?['total'] as int? ?? 0,
      imageUrl: images.isEmpty
          ? null
          : (images.first as Map<String, dynamic>)['url'] as String?,
    );
  }

  final String id;
  final String name;
  final String ownerId;
  final int trackCount;
  final String? imageUrl;
}