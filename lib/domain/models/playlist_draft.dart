import 'track.dart';

/// A playlist not created yet: what the preview screen shows (FR-8.1).
///
/// Immutable. Tracks keep their order; the cover is a mosaic of the first
/// tracks' covers ([coverUrls]).
class PlaylistDraft {
  const PlaylistDraft({
    required this.name,
    required this.tracks,
    this.artistNames = const {},
  });

  /// Provisional name (editable in the preview).
  final String name;
  final List<Track> tracks;

  /// Artist id → name for artists that may not be in the local database
  /// (Discover results, FR-10). Empty for drafts built from the library.
  final Map<String, String> artistNames;

  /// Up to 4 different cover URLs, in track order, for the mosaic.
  List<String> get coverUrls =>
      tracks.map((t) => t.coverUrl).nonNulls.toSet().take(4).toList();

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  PlaylistDraft copyWith({
    String? name,
    List<Track>? tracks,
    Map<String, String>? artistNames,
  }) {
    return PlaylistDraft(
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      artistNames: artistNames ?? this.artistNames,
    );
  }
}