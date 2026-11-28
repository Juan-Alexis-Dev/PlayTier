/// Kind of an own Discover parameter (FR-10.5).
enum DiscoverParameterKind { artist, genre }

/// An artist or genre chosen as an own Discover parameter (FR-10.5).
///
/// Immutable. [id] is the Spotify artist id or the lower-case genre name;
/// [label] is what the chip shows (the artist name or the genre).
class DiscoverParameter {
  const DiscoverParameter({
    required this.kind,
    required this.id,
    required this.label,
  });

  const DiscoverParameter.artist({required this.id, required this.label})
      : kind = DiscoverParameterKind.artist;

  const DiscoverParameter.genre(String genre)
      : kind = DiscoverParameterKind.genre,
        id = genre,
        label = genre;

  final DiscoverParameterKind kind;
  final String id;
  final String label;

  bool get isArtist => kind == DiscoverParameterKind.artist;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoverParameter && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'DiscoverParameter(${kind.name}, $id)';
}