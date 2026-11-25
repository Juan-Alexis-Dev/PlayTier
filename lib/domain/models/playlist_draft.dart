import 'track.dart';

/// A playlist not created yet: what the preview screen shows (FR-8.1).
///
/// Immutable. Tracks keep their order; the cover is a mosaic of the first
/// tracks' covers ([coverUrls]).
class PlaylistDraft {
  const PlaylistDraft({required this.name, required this.tracks});

  /// Provisional name (editable in the preview).
  final String name;
  final List<Track> tracks;

  /// Up to 4 different cover URLs, in track order, for the mosaic.
  List<String> get coverUrls =>
      tracks.map((t) => t.coverUrl).nonNulls.toSet().take(4).toList();

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  PlaylistDraft copyWith({String? name, List<Track>? tracks}) {
    return PlaylistDraft(
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
    );
  }
}