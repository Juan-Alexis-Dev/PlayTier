import 'dart:async';

import '../../../domain/models/playback_device.dart';
import '../../../domain/models/playback_exception.dart';
import '../../../domain/models/playback_state.dart';
import '../spotify/dto/spotify_device_dto.dart';
import '../spotify/dto/spotify_player_dto.dart';
import '../spotify/spotify_api_exception.dart';
import '../spotify/spotify_api_service.dart';
import 'playback_service.dart';

/// Desktop [PlaybackService] (Linux/Windows) using Spotify Connect through
/// the Web API (FR-11.3, FR-11.4).
///
/// The Spotify desktop app must be open to appear as a device. The state is
/// polled every [pollInterval] only while [state] has listeners; between
/// polls, use `PlaybackState.positionAt`.
class ConnectPlaybackService implements PlaybackService {
  ConnectPlaybackService(
    this._api, {
    this.pollInterval = const Duration(seconds: 5),
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  })  : _delay = delay ?? ((d) => Future<void>.delayed(d)),
        _clock = clock ?? DateTime.now;

  final SpotifyApiService _api;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  /// Time between `GET /me/player` calls (no sub-second polling, C-9).
  final Duration pollInterval;

  late final StreamController<PlaybackState?> _controller =
      StreamController.broadcast(onListen: _startPolling, onCancel: _stop);
  Timer? _timer;

  @override
  Stream<PlaybackState?> get state => _controller.stream;

  @override
  Future<void> playContext(String contextUri, {int startIndex = 0}) async {
    final device = await _targetDevice();
    await _guard(
      () => _api.startPlayback(
        deviceId: device.id,
        contextUri: contextUri,
        offsetPosition: startIndex,
      ),
    );
    // Spotify needs a moment before it accepts the shuffle change (spike).
    await _delay(const Duration(milliseconds: 500));
    await _guard(() => _api.setShuffle(false, deviceId: device.id));
    unawaited(_refresh());
  }

  @override
  Future<void> pause() => _command(_api.pausePlayback);

  @override
  Future<void> resume() => _command(_api.startPlayback);

  @override
  Future<void> next() => _command(_api.skipToNext);

  @override
  Future<void> previous() => _command(_api.skipToPrevious);

  @override
  Future<void> seek(Duration position) => _command(() => _api.seek(position));

  @override
  Future<void> setRepeat(RepeatMode mode) =>
      _command(() => _api.setRepeat(mode.name));

  @override
  Future<List<PlaybackDevice>> getDevices() async {
    final devices = await _guard(_api.getDevices);
    return devices.map((d) => d.toDevice()).nonNulls.toList();
  }

  /// After the transfer, [_targetDevice] picks it as the active device.
  @override
  Future<void> transferTo(String deviceId) =>
      _command(() => _api.transferPlayback(deviceId));

  @override
  Future<void> dispose() async {
    _stop();
    await _controller.close();
  }

  /// Active device, else the first usable computer, else any usable device.
  Future<SpotifyDeviceDto> _targetDevice() async {
    final devices = await _guard(_api.getDevices);
    final usable = devices.where((d) => d.id != null && !d.isRestricted);
    final device = usable.where((d) => d.isActive).firstOrNull ??
        usable.where((d) => d.type == 'Computer').firstOrNull ??
        usable.firstOrNull;
    if (device == null) {
      throw const PlaybackException(PlaybackErrorKind.noDevice);
    }
    return device;
  }

  /// Runs a simple command and refreshes the state right away.
  Future<void> _command(Future<void> Function() action) async {
    await _guard(action);
    unawaited(_refresh());
  }

  /// Maps Web API errors to [PlaybackException].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SpotifyApiException catch (e) {
      throw PlaybackException(
        e.statusCode == 404
            ? PlaybackErrorKind.noDevice
            : PlaybackErrorKind.rejected,
        e.message,
      );
    }
  }

  void _startPolling() {
    unawaited(_refresh());
    _timer = Timer.periodic(pollInterval, (_) => _refresh());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh() async {
    if (!_controller.hasListener) return;
    try {
      final player = await _api.getPlayer();
      if (!_controller.isClosed) _controller.add(toState(player, _clock()));
    } on Exception {
      // Keep the last state; the next poll tries again.
    }
  }

  /// Converts a Web API player into a [PlaybackState] read at [now].
  /// Visible for tests.
  static PlaybackState? toState(SpotifyPlayerDto? player, DateTime now) {
    final uri = player?.trackUri;
    if (player == null || uri == null) return null;
    return PlaybackState(
      trackUri: uri,
      trackName: player.trackName ?? '',
      artistNames: player.artistNames,
      albumName: player.albumName ?? '',
      duration: Duration(milliseconds: player.durationMs ?? 0),
      position: Duration(milliseconds: player.progressMs),
      isPlaying: player.isPlaying,
      updatedAt: now,
      isShuffling: player.shuffleState,
      repeatMode: RepeatMode.values.asNameMap()[player.repeatState] ??
          RepeatMode.off,
      contextUri: player.contextUri,
      deviceName: player.device?.name,
      coverUrl: player.coverUrl,
    );
  }
}