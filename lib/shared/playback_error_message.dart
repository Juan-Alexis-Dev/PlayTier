import '../domain/models/playback_exception.dart';

/// Text shown to the user when playback fails (FR-11.5). Shared by every
/// ViewModel that starts playback.
String playbackErrorMessage(Exception error) {
  if (error is! PlaybackException) return 'Could not start playback.';
  return switch (error.kind) {
    PlaybackErrorKind.noDevice =>
      'No active Spotify device. Open Spotify and try again.',
    PlaybackErrorKind.spotifyAppUnavailable =>
      'Could not connect to the Spotify app. Open it and try again.',
    PlaybackErrorKind.rejected =>
      'Spotify rejected the request. A Premium account is required.',
  };
}