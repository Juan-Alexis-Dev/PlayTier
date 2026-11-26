import '../../../domain/models/playback_device.dart';
import '../../../domain/models/playback_state.dart';

/// Controls the official Spotify app (the app never plays audio itself).
///
/// Two implementations, chosen in `app/dependencies.dart`:
/// - `AppRemotePlaybackService` on Android (`spotify_sdk`, push updates).
/// - `ConnectPlaybackService` on Linux/Windows (Web API, polling).
///
/// Methods throw `PlaybackException` (domain); `PlaybackRepository` turns them into
/// `Result`s.
abstract interface class PlaybackService {
  /// Player state; null when nothing is playing. Desktop polls only while
  /// someone listens, so cancel the subscription when it is not needed.
  Stream<PlaybackState?> get state;

  /// Plays the playlist [contextUri] in order, starting at [startIndex],
  /// with Spotify's own shuffle off.
  Future<void> playContext(String contextUri, {int startIndex = 0});

  Future<void> pause();
  Future<void> resume();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setRepeat(RepeatMode mode);

  /// Devices where Spotify is open and can be controlled (FR-11.2).
  Future<List<PlaybackDevice>> getDevices();

  /// Moves playback to the device [deviceId] (e.g. the PC from the phone).
  Future<void> transferTo(String deviceId);

  /// Stops timers and subscriptions.
  Future<void> dispose();
}