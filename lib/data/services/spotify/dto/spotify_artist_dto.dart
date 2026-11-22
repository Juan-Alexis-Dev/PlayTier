/// Artist from `GET /artists/{id}`, or the simplified artist inside a track
/// (which has no genres).
class SpotifyArtistDto {
  const SpotifyArtistDto({
    required this.id,
    required this.name,
    this.genres = const [],
  });

  factory SpotifyArtistDto.fromJson(Map<String, dynamic> json) {
    return SpotifyArtistDto(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      genres: [
        for (final genre in json['genres'] as List<dynamic>? ?? const [])
          if (genre is String) genre,
      ],
    );
  }

  final String id;
  final String name;
  final List<String> genres;
}