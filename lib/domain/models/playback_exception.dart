/// Why a playback command failed.
enum PlaybackErrorKind {
  /// No Spotify device is open or active (FR-11.5).
  noDevice,

  /// The Spotify app did not answer or refused the connection (Android).
  spotifyAppUnavailable,

  /// Spotify refused the command (e.g. account without Premium).
  rejected,
}

/// Error thrown by a `PlaybackService`.
class PlaybackException implements Exception {
  const PlaybackException(this.kind, [this.message = '']);

  final PlaybackErrorKind kind;
  final String message;

  @override
  String toString() => 'PlaybackException(${kind.name}, $message)';
}