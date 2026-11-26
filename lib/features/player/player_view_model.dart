import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/levels_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../domain/models/like_level.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/result.dart';
import '../../shared/playback_error_message.dart';

/// App-wide player state, shared by the mini-player and Now Playing.
///
/// Listens to the player and the like levels only while the user is
/// logged in ([init]), so
/// desktop does not poll Spotify before login. While playing, it notifies
/// once per second so the position (estimated with
/// [PlaybackState.positionAt]) moves smoothly between desktop polls.
///
/// Commands return an error message for the View, or null on success.
class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({
    required this._playback,
    required this._levels,
    required this._loggedIn,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PlaybackRepository _playback;
  final LevelsRepository _levels;
  final ValueListenable<bool> _loggedIn;
  final DateTime Function() _clock;

  StreamSubscription<PlaybackState?>? _subscription;
  StreamSubscription<Map<String, int>>? _levelsSubscription;
  Timer? _ticker;
  PlaybackState? _state;
  Map<String, int> _levelsById = const {};

  /// Current player state; null when nothing is playing.
  PlaybackState? get state => _state;

  bool get isPlaying => _state?.isPlaying ?? false;

  /// Name of the playlist the app started ("Playing from"), if known.
  String? get contextName {
    final state = _state;
    return state == null ? null : _playback.contextNameOf(state);
  }

  /// Like level of the current track; null when it is not in the main
  /// playlist (every main track has a level row after sync).
  int? get currentLevel {
    final state = _state;
    return state == null ? null : _levelsById[state.trackId];
  }

  /// Estimated position now.
  Duration get position => _state?.positionAt(_clock()) ?? Duration.zero;

  /// Position as a fraction 0–1 of the track duration.
  double get progress {
    final duration = _state?.duration ?? Duration.zero;
    if (duration == Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Starts following the login state. Call once.
  void init() {
    _loggedIn.addListener(_onLoginChanged);
    _onLoginChanged();
  }

  Future<String?> togglePlayPause() async {
    final before = _state;
    if (before == null) return null;

    final message = await _command(
      before.isPlaying ? _playback.pause : _playback.resume,
    );
    // Desktop only sees the change at the next poll; show it now.
    if (message == null && identical(_state, before)) {
      final now = _clock();
      _setState(
        before.copyWith(
          isPlaying: !before.isPlaying,
          position: before.positionAt(now),
          updatedAt: now,
        ),
      );
    }
    return message;
  }

  Future<String?> next() => _command(_playback.next);
  Future<String?> previous() => _command(_playback.previous);

  Future<String?> seek(Duration position) async {
    final before = _state;
    if (before == null) return null;

    final message = await _command(() => _playback.seek(position));
    if (message == null && identical(_state, before)) {
      _setState(before.copyWith(position: position, updatedAt: _clock()));
    }
    return message;
  }

  /// Off → whole playlist → this track → off.
  Future<String?> cycleRepeat() async {
    final before = _state;
    if (before == null) return null;

    final next = switch (before.repeatMode) {
      RepeatMode.off => RepeatMode.context,
      RepeatMode.context => RepeatMode.track,
      RepeatMode.track => RepeatMode.off,
    };
    final message = await _command(() => _playback.setRepeat(next));
    if (message == null && identical(_state, before)) {
      _setState(before.copyWith(repeatMode: next));
    }
    return message;
  }

  /// Sets the like level of the current track (FR-12.3).
  Future<String?> setLevel(int value) async {
    final state = _state;
    if (state == null || currentLevel == null) return null;

    final result = await _levels.setLevel(state.trackId, LikeLevel(value));
    return switch (result) {
      Ok() => null,
      Error() => 'Could not save the level.',
    };
  }

  void _onLoginChanged() {
    if (_loggedIn.value) {
      _subscription ??= _playback.state.listen(_setState);
      _levelsSubscription ??= _levels.watchLevels().listen((levels) {
        _levelsById = levels;
        notifyListeners();
      });
    } else {
      unawaited(_subscription?.cancel());
      unawaited(_levelsSubscription?.cancel());
      _subscription = null;
      _levelsSubscription = null;
      _levelsById = const {};
      _setState(null);
    }
  }

  void _setState(PlaybackState? state) {
    _state = state;
    if (isPlaying) {
      _ticker ??=
          Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  Future<String?> _command(Future<Result<void>> Function() action) async {
    final result = await action();
    return switch (result) {
      Ok() => null,
      Error(:final error) => playbackErrorMessage(error),
    };
  }

  @override
  void dispose() {
    _loggedIn.removeListener(_onLoginChanged);
    unawaited(_subscription?.cancel());
    unawaited(_levelsSubscription?.cancel());
    _ticker?.cancel();
    super.dispose();
  }
}