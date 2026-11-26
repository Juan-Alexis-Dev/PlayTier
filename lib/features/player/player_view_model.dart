import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/playback_repository.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/result.dart';
import '../../shared/playback_error_message.dart';

/// App-wide player state, shared by the mini-player and Now Playing.
///
/// Listens to the player only while the user is logged in ([init]), so
/// desktop does not poll Spotify before login. While playing, it notifies
/// once per second so the position (estimated with
/// [PlaybackState.positionAt]) moves smoothly between desktop polls.
///
/// Commands return an error message for the View, or null on success.
class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({
    required this._playback,
    required this._loggedIn,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PlaybackRepository _playback;
  final ValueListenable<bool> _loggedIn;
  final DateTime Function() _clock;

  StreamSubscription<PlaybackState?>? _subscription;
  Timer? _ticker;
  PlaybackState? _state;

  /// Current player state; null when nothing is playing.
  PlaybackState? get state => _state;

  bool get isPlaying => _state?.isPlaying ?? false;

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

  void _onLoginChanged() {
    if (_loggedIn.value) {
      _subscription ??= _playback.state.listen(_setState);
    } else {
      unawaited(_subscription?.cancel());
      _subscription = null;
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
    _ticker?.cancel();
    super.dispose();
  }
}