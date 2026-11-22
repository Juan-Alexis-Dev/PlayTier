/// Repeat mode of the Spotify player.
enum RepeatMode { off, context, track }

/// Snapshot of the Spotify player: current track, position and options.
///
/// Immutable. [position] is the position at [updatedAt]; use [positionAt]
/// to estimate it later without asking Spotify again (FR-11.4).
class PlaybackState {
  const PlaybackState({
    required this.trackUri,
    required this.trackName,
    required this.artistNames,
    required this.albumName,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.updatedAt,
    this.isShuffling = false,
    this.repeatMode = RepeatMode.off,
    this.contextUri,
    this.deviceName,
    this.coverUrl,
  });

  /// Spotify URI of the current track.
  final String trackUri;
  final String trackName;
  final List<String> artistNames;
  final String albumName;
  final Duration duration;

  /// Position when this state was read ([updatedAt]).
  final Duration position;
  final bool isPlaying;
  final DateTime updatedAt;

  final bool isShuffling;
  final RepeatMode repeatMode;

  /// URI of the playlist being played, if known (not given on Android).
  final String? contextUri;

  /// Name of the device playing, if known (not given on Android).
  final String? deviceName;

  /// Cover URL, if known (not given on Android).
  final String? coverUrl;

  /// Track id taken from [trackUri] (`spotify:track:<id>`).
  String get trackId => trackUri.split(':').last;

  /// Estimated position at [now]: grows while playing, capped at [duration].
  Duration positionAt(DateTime now) {
    if (!isPlaying) return position;
    final estimate = position + now.difference(updatedAt);
    if (estimate < Duration.zero) return Duration.zero;
    return estimate > duration ? duration : estimate;
  }

  PlaybackState copyWith({
    Duration? position,
    bool? isPlaying,
    DateTime? updatedAt,
    bool? isShuffling,
    RepeatMode? repeatMode,
  }) {
    return PlaybackState(
      trackUri: trackUri,
      trackName: trackName,
      artistNames: artistNames,
      albumName: albumName,
      duration: duration,
      position: position ?? this.position,
      isPlaying: isPlaying ?? this.isPlaying,
      updatedAt: updatedAt ?? this.updatedAt,
      isShuffling: isShuffling ?? this.isShuffling,
      repeatMode: repeatMode ?? this.repeatMode,
      contextUri: contextUri,
      deviceName: deviceName,
      coverUrl: coverUrl,
    );
  }

  @override
  String toString() => 'PlaybackState($trackName, $position, '
      '${isPlaying ? 'playing' : 'paused'})';
}