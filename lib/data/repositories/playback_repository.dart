import '../../domain/models/playback_state.dart';
import '../../domain/models/result.dart';
import '../services/playback/playback_service.dart';

/// Playback of Spotify playlists through the platform [PlaybackService].
///
/// Returns [Result]s so no exception reaches a View. Grows in v0.3
/// (`playShuffled` and round regeneration).
class PlaybackRepository {
  PlaybackRepository(this._service);

  final PlaybackService _service;

  /// Player state; null when nothing is playing.
  Stream<PlaybackState?> get state => _service.state;

  /// Plays the Spotify playlist [contextUri] in order from [startIndex]
  /// (e.g. `spotify:playlist:<id>`).
  Future<Result<void>> playList(String contextUri, {int startIndex = 0}) =>
      _run(() => _service.playContext(contextUri, startIndex: startIndex));

  Future<Result<void>> pause() => _run(_service.pause);
  Future<Result<void>> resume() => _run(_service.resume);
  Future<Result<void>> next() => _run(_service.next);
  Future<Result<void>> previous() => _run(_service.previous);

  Future<Result<void>> seek(Duration position) =>
      _run(() => _service.seek(position));

  Future<Result<void>> setRepeat(RepeatMode mode) =>
      _run(() => _service.setRepeat(mode));

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}