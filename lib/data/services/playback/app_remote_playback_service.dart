import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:spotify_sdk/spotify_sdk.dart' as sdk;

import '../../../app/config.dart';
import '../../../domain/models/playback_device.dart';
import '../../../domain/models/playback_exception.dart';
import '../../../domain/models/playback_state.dart';
import '../spotify/spotify_api_exception.dart';
import '../spotify/spotify_api_service.dart';
import 'playback_service.dart';

/// Android [PlaybackService] using the Spotify App Remote SDK (FR-11.3).
///
/// Connects lazily on the first command. Workarounds from the spike
/// (`docs/spikes/playback.md` §5.1):
/// - if the connection is refused, authorize once with
///   `getAccessToken(scope: 'app-remote-control')` from the foreground,
///   then connect again;
/// - `switchToLocalDevice()` before playing, so music starts on the phone
///   (skipped once the user picked a device, FR-11.2);
/// - timeouts on every connection step, because the SDK can wait forever.
///
/// Devices are listed and switched through the Web API (Spotify Connect);
/// the phone's Spotify app then forwards the App Remote commands to the
/// chosen device.
class AppRemotePlaybackService implements PlaybackService {
  AppRemotePlaybackService(
    this._config,
    this._api, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppConfig _config;
  final SpotifyApiService _api;
  final DateTime Function() _clock;

  /// True after [transferTo]: play where the user chose, not on the phone.
  bool _keepDevice = false;

  static const _connectTimeout = Duration(seconds: 30);
  static const _authorizeTimeout = Duration(seconds: 90);

  final _controller = StreamController<PlaybackState?>.broadcast();
  StreamSubscription<sdk.PlayerState>? _playerSub;
  bool _connected = false;
  Future<void>? _connecting;

  @override
  Stream<PlaybackState?> get state => _controller.stream;

  @override
  Future<void> playContext(String contextUri, {int startIndex = 0}) {
    return _run(() async {
      if (!_keepDevice) await sdk.SpotifySdk.switchToLocalDevice();
      // play() resumes when the context is already loaded; skipToIndex()
      // always starts it at the given track.
      await sdk.SpotifySdk.skipToIndex(
        spotifyUri: contextUri,
        trackIndex: startIndex,
      );
      await sdk.SpotifySdk.setShuffle(shuffle: false);
    });
  }

  @override
  Future<void> pause() => _run(sdk.SpotifySdk.pause);

  @override
  Future<void> resume() => _run(sdk.SpotifySdk.resume);

  @override
  Future<void> next() => _run(sdk.SpotifySdk.skipNext);

  @override
  Future<void> previous() => _run(sdk.SpotifySdk.skipPrevious);

  @override
  Future<void> seek(Duration position) => _run(
        () => sdk.SpotifySdk.seekTo(
          positionedMilliseconds: position.inMilliseconds,
        ),
      );

  @override
  Future<void> setRepeat(RepeatMode mode) => _run(
        () => sdk.SpotifySdk.setRepeatMode(
          repeatMode: switch (mode) {
            RepeatMode.off => sdk.SpotifyRepeatMode.off,
            RepeatMode.context => sdk.SpotifyRepeatMode.context,
            RepeatMode.track => sdk.SpotifyRepeatMode.track,
          },
        ),
      );

  @override
  Future<List<PlaybackDevice>> getDevices() async {
    final devices = await _web(_api.getDevices);
    return devices.map((d) => d.toDevice()).nonNulls.toList();
  }

  @override
  Future<void> transferTo(String deviceId) async {
    await _web(() => _api.transferPlayback(deviceId));
    _keepDevice = true;
  }

  @override
  Future<void> dispose() async {
    await _playerSub?.cancel();
    await _controller.close();
    if (_connected) await sdk.SpotifySdk.disconnect();
  }

  /// Connects if needed, runs [action] and maps SDK errors.
  Future<void> _run(Future<void> Function() action) async {
    await _ensureConnected();
    try {
      await action();
    } on PlaybackException {
      rethrow;
    } on Exception catch (e) {
      // The connection may have dropped (e.g. Spotify was closed).
      _connected = false;
      throw PlaybackException(PlaybackErrorKind.spotifyAppUnavailable, '$e');
    }
  }

  /// Maps Web API errors to [PlaybackException].
  Future<T> _web<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SpotifyApiException catch (e) {
      debugPrint('Spotify Web API error: ${e.statusCode} ${e.message}');
      throw PlaybackException(
        e.statusCode == 404
            ? PlaybackErrorKind.noDevice
            : PlaybackErrorKind.rejected,
        e.message,
      );
    }
  }

  /// Shares one connection attempt between parallel commands.
  Future<void> _ensureConnected() {
    if (_connected) return Future.value();
    return _connecting ??= _connectWithAuthorization().whenComplete(() {
      _connecting = null;
    });
  }

  Future<void> _connectWithAuthorization() async {
    try {
      await _connect();
    } on Exception {
      // First run: the consent screen must be opened from the foreground.
      try {
        await sdk.SpotifySdk.getAccessToken(
          clientId: _config.spotifyClientId,
          redirectUrl: _config.spotifyRedirectUriAppRemote,
          scope: 'app-remote-control',
        ).timeout(_authorizeTimeout);
        await _connect();
      } on Exception catch (e) {
        throw PlaybackException(PlaybackErrorKind.spotifyAppUnavailable, '$e');
      }
    }
  }

  Future<void> _connect() async {
    final ok = await sdk.SpotifySdk.connectToSpotifyRemote(
      clientId: _config.spotifyClientId,
      redirectUrl: _config.spotifyRedirectUriAppRemote,
    ).timeout(_connectTimeout);
    if (!ok) {
      throw const PlaybackException(PlaybackErrorKind.spotifyAppUnavailable);
    }
    _connected = true;
    await _playerSub?.cancel();
    _playerSub = sdk.SpotifySdk.subscribePlayerState().listen(
      (s) => _controller.add(_toState(s)),
      onError: (Object _) => _connected = false,
    );
  }

  PlaybackState? _toState(sdk.PlayerState s) {
    final track = s.track;
    if (track == null) return null;
    return PlaybackState(
      trackUri: track.uri,
      trackName: track.name,
      artistNames: [for (final artist in track.artists) artist.name ?? ''],
      albumName: track.album.name ?? '',
      duration: Duration(milliseconds: track.duration),
      position: Duration(milliseconds: s.playbackPosition),
      isPlaying: !s.isPaused,
      updatedAt: _clock(),
      isShuffling: s.playbackOptions.isShuffling,
      repeatMode: switch (s.playbackOptions.repeatMode) {
        sdk.SpotifyRepeatMode.off => RepeatMode.off,
        sdk.SpotifyRepeatMode.context => RepeatMode.context,
        sdk.SpotifyRepeatMode.track => RepeatMode.track,
      },
    );
  }
}