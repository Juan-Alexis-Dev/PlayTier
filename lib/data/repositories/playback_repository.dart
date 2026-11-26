import 'dart:async';
import 'dart:math';

import '../../domain/engines/weighted_shuffle.dart';
import '../../domain/models/playback_device.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/result.dart';
import '../../domain/models/track.dart';
import '../services/playback/playback_service.dart';
import 'levels_repository.dart';
import 'playlist_repository.dart';

/// Playback of Spotify playlists through the platform [PlaybackService].
///
/// Returns [Result]s so no exception reaches a View.
///
/// Weighted shuffle (FR-4): [playShuffled] writes one round to the playback
/// playlist and plays it in order. While the session is active, this
/// repository follows the player and, a few tracks before the end, appends
/// a new round (with the current levels) so playback never stops (FR-4.5).
/// If the app is closed, Spotify simply plays what was already written.
class PlaybackRepository {
  PlaybackRepository(
    this._service, {
    required this._playlists,
    required this._levels,
    Random? random,
  }) : _random = random ?? Random();

  final PlaybackService _service;
  final PlaylistRepository _playlists;
  final LevelsRepository _levels;
  final Random _random;

  /// The next round is appended when this many tracks (or fewer) are left.
  static const appendAhead = 3;

  /// Spotify limit of items per playlist; no rounds are appended past it.
  static const maxPlaylistItems = 10000;

  /// How far forward/backward a new track is searched in the queue
  /// (skips missed between two desktop polls, or "previous").
  static const _searchWindow = 20;

  // Shuffle session (null tracks = no session).
  List<Track>? _shuffleTracks;
  String? _shuffleContextId;
  final List<Track> _queue = [];
  int _cursor = 0;
  bool _started = false;
  bool _appending = false;
  int _sessionId = 0;
  StreamSubscription<PlaybackState?>? _shuffleSub;

  // What the app last started, to show "Playing from" (FR-12.1).
  String? _contextName;
  String? _contextId;

  /// Player state; null when nothing is playing.
  Stream<PlaybackState?> get state => _service.state;

  /// Whether a weighted shuffle session is running.
  bool get isShuffleActive => _shuffleTracks != null;

  /// Name given to the last [playList] / [playShuffled] call, while
  /// [state] still plays that context; otherwise null.
  ///
  /// Android does not report the context, so there the name is kept until
  /// the app starts something else.
  String? contextNameOf(PlaybackState state) {
    final id = _contextId;
    if (id == null) return null;
    final uri = state.contextUri;
    if (uri != null && !uri.endsWith(id)) return null;
    return _contextName;
  }

  /// Plays the Spotify playlist [contextUri] in order from [startIndex]
  /// (e.g. `spotify:playlist:<id>`). Ends any shuffle session.
  /// [name] is shown as "Playing from" in Now Playing.
  Future<Result<void>> playList(
    String contextUri, {
    int startIndex = 0,
    String? name,
  }) async {
    await stopShuffle();
    final result = await _run(
      () => _service.playContext(contextUri, startIndex: startIndex),
    );
    if (result is Ok) _setContext(contextUri, name);
    return result;
  }

  /// Starts a weighted shuffle of [tracks] (FR-4): writes the first round
  /// to the playback playlist and plays it from the start.
  /// [name] is shown as "Playing from" in Now Playing.
  Future<Result<void>> playShuffled(List<Track> tracks, {String? name}) async {
    await stopShuffle();
    if (tracks.isEmpty) return const Result.ok(null);

    try {
      final round = await _nextRound(tracks);
      final written = await _playlists
          .writePlaybackPlaylist([for (final t in round) t.uri]);
      final String contextUri;
      switch (written) {
        case Ok(:final value):
          contextUri = value;
        case Error(:final error):
          return Result.error(error);
      }

      await _service.playContext(contextUri, startIndex: 0);
      _setContext(contextUri, name);

      _sessionId++;
      _shuffleTracks = tracks;
      _shuffleContextId = contextUri.split(':').last;
      _queue
        ..clear()
        ..addAll(round);
      _cursor = 0;
      _started = false;
      _shuffleSub = _service.state.listen(_onState);
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Ends the shuffle session. What was already written keeps playing.
  Future<void> stopShuffle() async {
    _sessionId++;
    _shuffleTracks = null;
    _shuffleContextId = null;
    _queue.clear();
    await _shuffleSub?.cancel();
    _shuffleSub = null;
  }

  Future<Result<void>> pause() => _run(_service.pause);
  Future<Result<void>> resume() => _run(_service.resume);
  Future<Result<void>> next() => _run(_service.next);
  Future<Result<void>> previous() => _run(_service.previous);

  Future<Result<void>> seek(Duration position) =>
      _run(() => _service.seek(position));

  Future<Result<void>> setRepeat(RepeatMode mode) =>
      _run(() => _service.setRepeat(mode));

  /// Devices where Spotify is open (FR-11.2).
  Future<Result<List<PlaybackDevice>>> getDevices() async {
    try {
      return Result.ok(await _service.getDevices());
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Moves playback to [deviceId]. A shuffle session keeps going: the
  /// context does not change.
  Future<Result<void>> transferTo(String deviceId) =>
      _run(() => _service.transferTo(deviceId));

  void _setContext(String contextUri, String? name) {
    _contextId = name == null ? null : contextUri.split(':').last;
    _contextName = name;
  }

  void _onState(PlaybackState? state) {
    if (state == null || _queue.isEmpty) return;

    // Ignore old states (desktop polling) until the round really starts.
    if (!_started) {
      if (state.trackUri != _queue.first.uri) return;
      _started = true;
    }

    final context = state.contextUri;
    if (context != null && !context.endsWith(_shuffleContextId!)) {
      unawaited(stopShuffle()); // The user played something else.
      return;
    }

    if (state.trackUri != _queue[_cursor].uri) {
      final index = _find(state.trackUri);
      if (index == null) {
        unawaited(stopShuffle());
        return;
      }
      _cursor = index;
    }

    if (_queue.length - _cursor <= appendAhead) unawaited(_appendRound());
  }

  /// Index of [uri] near the cursor: forward first (next / skips), then
  /// backward (previous), then the start (Spotify repeated the playlist).
  int? _find(String uri) {
    final end = min(_queue.length - 1, _cursor + _searchWindow);
    for (var i = _cursor + 1; i <= end; i++) {
      if (_queue[i].uri == uri) return i;
    }
    final start = max(0, _cursor - _searchWindow);
    for (var i = _cursor - 1; i >= start; i--) {
      if (_queue[i].uri == uri) return i;
    }
    return _queue.first.uri == uri ? 0 : null;
  }

  Future<void> _appendRound() async {
    final tracks = _shuffleTracks;
    if (_appending || tracks == null) return;
    _appending = true;
    final session = _sessionId;
    try {
      final round = await _nextRound(tracks, avoidFirst: _queue.last.id);
      if (_queue.length + round.length > maxPlaylistItems) return;

      final result = await _playlists
          .appendToPlaybackPlaylist([for (final t in round) t.uri]);
      if (result is Ok && session == _sessionId) _queue.addAll(round);
      // On error nothing is added; the next player state retries.
    } on Exception {
      // Levels could not be read; the next player state retries.
    } finally {
      _appending = false;
    }
  }

  /// A new round with the current levels (they may change while playing).
  Future<List<Track>> _nextRound(
    List<Track> tracks, {
    String? avoidFirst,
  }) async {
    final levels = await _levels.watchLevels().first;
    return WeightedShuffle.generate(
      tracks,
      levels: levels,
      avoidFirst: avoidFirst,
      random: _random,
    );
  }

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}