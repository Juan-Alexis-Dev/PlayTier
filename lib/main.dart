// SPIKE v0.0a — Steps 1–6: PKCE login (desktop + Android), reading the main
// playlist with pagination, playing it on a Spotify Connect device (desktop),
// spotify_sdk App Remote (Android) and writing a private playback playlist
// (150 tracks in chunks of 100) that plays in order.
// Throwaway code: lives only in the `spike/playback` branch.
//
// Run with:
//   flutter run -d linux --dart-define-from-file=config.json
//   flutter run -d <android-device-id> --dart-define-from-file=config.json

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

const clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
const desktopRedirectUri = String.fromEnvironment('SPOTIFY_REDIRECT_URI_DESKTOP');
const androidRedirectUri = String.fromEnvironment('SPOTIFY_REDIRECT_URI_ANDROID');
const mainPlaylistId = String.fromEnvironment('SPOTIFY_MAIN_PLAYLIST_ID');
const playbackPlaylistName = 'PlayTier — Playback';
const appRemoteRedirectUri =
    String.fromEnvironment('SPOTIFY_REDIRECT_URI_APP_REMOTE');

final redirectUri = Platform.isAndroid ? androidRedirectUri : desktopRedirectUri;

// Scopes needed for the whole spike (read playlists, control playback, create playlists).
const scopes = [
  'playlist-read-private',
  'playlist-read-collaborative',
  'playlist-modify-private',
  'playlist-modify-public',
  'user-read-playback-state',
  'user-modify-playback-state',
];

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12C66B),
          brightness: Brightness.dark,
        ),
      ),
      home: const LoginSpikeScreen(),
    );
  }
}

class LoginSpikeScreen extends StatefulWidget {
  const LoginSpikeScreen({super.key});

  @override
  State<LoginSpikeScreen> createState() => _LoginSpikeScreenState();
}

class _LoginSpikeScreenState extends State<LoginSpikeScreen> {
  String _status = 'Not logged in';
  bool _loading = false;
  String? _token;
  List<SpikeTrack> _tracks = [];
  List<SpikeDevice> _devices = [];
  String? _selectedDeviceId;

  // Step 6: playback playlist
  String? _playbackPlaylistId;
  List<String>? _writtenUris; // exact order written to the playlist
  Map<String, SpikeTrack> _trackByUri = {};
  int _expectedIndex = 0; // position that should be playing now
  int _previewChunk = 0; // which chunk of 100 is shown in the list

  // Android App Remote
  bool _remoteAuthorized = false;
  bool _remoteConnected = false;
  PlayerState? _playerState;
  StreamSubscription<PlayerState>? _playerSub;
  final _positionClock = Stopwatch(); // time since the last PlayerState
  Timer? _ticker; // refreshes the position shown on screen

  @override
  void dispose() {
    _playerSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _status = 'Waiting for login in the browser...';
    });
    try {
      final token = await loginWithSpotify();
      final me = await http.get(
        Uri.https('api.spotify.com', '/v1/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final body = jsonDecode(me.body) as Map<String, dynamic>;
      setState(() {
        _token = token;
        _status = 'Logged in as: ${body['display_name'] ?? body['id']}\n'
            'HTTP ${me.statusCode}\n'
            'Token: ${token.substring(0, 12)}...';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPlaylist() async {
    setState(() {
      _loading = true;
      _status = 'Loading main playlist...';
    });
    final stopwatch = Stopwatch()..start();
    try {
      final tracks = await fetchPlaylistTracks(_token!, mainPlaylistId);
      debugPrint('--- First 20 tracks ---');
      for (final (i, track) in tracks.take(20).indexed) {
        debugPrint('${i + 1}. $track');
      }
      // Tracks that will NOT be written to the playback playlist.
      final excluded = tracks.where((t) => t.isLocal || !t.isPlayable).toList();
      for (final t in excluded) {
        debugPrint('Excluded: $t');
      }
      setState(() {
        _tracks = tracks;
        _writtenUris = null; // show the main playlist preview again
        _status = 'Loaded ${tracks.length} tracks '
            '(${excluded.length} local/not playable) '
            'in ${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _status = 'Loading devices...';
    });
    try {
      final devices = await fetchDevices(_token!);
      for (final device in devices) {
        debugPrint(device.toString());
      }
      // Keep the user's choice if that device is still there;
      // otherwise pick the default for this platform.
      final keepSelection = devices.any((d) => d.id == _selectedDeviceId);
      setState(() {
        _devices = devices;
        if (!keepSelection) _selectedDeviceId = _defaultDevice(devices)?.id;
        _status = devices.isEmpty
            ? 'No devices found: open the Spotify desktop app and try again'
            : 'Found ${devices.length} device(s)';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Default device: on Android this phone, on desktop the active device
  /// or the first computer.
  SpikeDevice? _defaultDevice(List<SpikeDevice> devices) {
    if (Platform.isAndroid) {
      final phone = devices.where((d) => d.type == 'Smartphone').firstOrNull;
      if (phone != null) return phone;
    }
    return devices.where((d) => d.isActive).firstOrNull ??
        devices.where((d) => d.type == 'Computer').firstOrNull ??
        devices.firstOrNull;
  }

  /// Android: if another device (e.g. the PC) is the active Spotify Connect
  /// device, move playback to this phone first (without starting music).
  /// Needs the Web API login; skipped if not logged in.
  Future<void> _makePhoneActive() async {
    if (_token == null) return;
    final devices = await fetchDevices(_token!);
    final phone = devices.where((d) => d.type == 'Smartphone').firstOrNull;
    if (phone?.id == null || phone!.isActive) return;
    debugPrint('Transferring playback to "${phone.name}" before App Remote');
    await transferPlayback(_token!, deviceId: phone.id!);
    setState(() {
      _devices = devices;
      _selectedDeviceId = phone.id;
    });
  }

  // -------------------------------------------------------------------------
  // Step 6: write a private playlist and play it in order
  // -------------------------------------------------------------------------

  Future<void> _writeAndPlayInOrder() async {
    setState(() {
      _loading = true;
      _status = 'Writing playback playlist...';
    });
    try {
      // 1. URIs of the main playlist that can actually be played, reversed
      //    (so the order is clearly different from the original).
      final source = _tracks
          .where((t) => t.uri != null && !t.isLocal && t.isPlayable)
          .toList()
          .reversed
          .toList();
      if (source.isEmpty) throw Exception('Load the main playlist first');
      _trackByUri = {for (final t in source) t.uri!: t};
      final uris = [for (final t in source) t.uri!];

      // 2. Find (or create once) the private playback playlist.
      final stopwatch = Stopwatch()..start();
      _playbackPlaylistId ??=
          await findOrCreatePlaylist(_token!, playbackPlaylistName);

      // 3. Replace its items in chunks of 100.
      await replacePlaylistItems(_token!, _playbackPlaylistId!, uris);
      final writeMs = stopwatch.elapsedMilliseconds;

      debugPrint('--- Written order (first 10) ---');
      for (final (i, uri) in uris.take(10).indexed) {
        debugPrint('${i + 1}. ${_trackByUri[uri]?.name}');
      }

      // 4. Play from position 0, then turn shuffle off.
      await startPlayback(
        _token!,
        deviceId: _selectedDeviceId!,
        contextUri: 'spotify:playlist:$_playbackPlaylistId',
        offsetPosition: 0,
      );
      // Player commands are not guaranteed to run in order: give the
      // device a moment to become active before changing shuffle.
      await Future.delayed(const Duration(milliseconds: 500));
      await setShuffle(_token!, deviceId: _selectedDeviceId!, state: false);

      setState(() {
        _writtenUris = uris;
        _expectedIndex = 0;
        _previewChunk = 0;
        _status = 'Wrote ${uris.length} tracks in $writeMs ms. '
            'Playing in order — tap "Next & check".';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Skips to the next track (or only checks, if [skip] is false) and compares
  /// what Spotify is playing with the written order.
  Future<void> _nextAndCheck({bool skip = true}) async {
    setState(() => _loading = true);
    try {
      if (skip) {
        await skipToNext(_token!, deviceId: _selectedDeviceId!);
        _expectedIndex++;
      }
      await Future.delayed(const Duration(milliseconds: 1200));
      final state = await fetchPlaybackState(_token!);
      final playingUri = state?['item']?['uri'] as String?;
      final expectedUri = _writtenUris![_expectedIndex];
      final ok = playingUri == expectedUri;
      debugPrint(
        '${ok ? 'OK' : 'MISMATCH'} #${_expectedIndex + 1}: '
        'playing ${state?['item']?['name']} / expected ${_trackByUri[expectedUri]?.name} '
        '(shuffle ${state?['shuffle_state']})',
      );
      setState(() {
        // Keep the preview on the chunk that contains the current track.
        _previewChunk = _expectedIndex ~/ 100;
        _status = '${ok ? '✅' : '❌'} #${_expectedIndex + 1} of ${_writtenUris!.length}\n'
            'Playing:  ${state?['item']?['name'] ?? '(nothing)'}\n'
            'Expected: ${_trackByUri[expectedUri]?.name}\n'
            'Shuffle: ${state?['shuffle_state']}';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _playMainPlaylist() async {
    setState(() {
      _loading = true;
      _status = 'Starting playback...';
    });
    try {
      await startPlayback(
        _token!,
        deviceId: _selectedDeviceId!,
        contextUri: 'spotify:playlist:$mainPlaylistId',
      );
      final device = _devices.firstWhere((d) => d.id == _selectedDeviceId);
      setState(() => _status = 'Playing main playlist on "${device.name}"');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Android: spotify_sdk App Remote
  // -------------------------------------------------------------------------

  /// Opens the Spotify authorization screen FROM PlayTier (foreground), so
  /// Android does not block it. Only needed once per install.
  Future<void> _authorizeAppRemote() async {
    setState(() {
      _loading = true;
      _status = 'Opening Spotify authorization...';
    });
    try {
      await _makePhoneActive();
      final token = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: appRemoteRedirectUri,
        scope: 'app-remote-control',
      ).timeout(const Duration(seconds: 90));
      debugPrint('App Remote authorized, token: ${token.substring(0, 12)}...');
      setState(() {
        _remoteAuthorized = true;
        _status = 'Authorized. Now tap "Connect App Remote".';
      });
    } on SpotifyException catch (e) {
      setState(() => _status = 'Spotify error: $e');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _connectAppRemote() async {
    setState(() {
      _loading = true;
      _status = 'Connecting to the Spotify app...';
    });
    try {
      await _makePhoneActive();
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: clientId,
        redirectUrl: appRemoteRedirectUri,
      ).timeout(const Duration(seconds: 30));
      if (!connected) throw Exception('connectToSpotifyRemote returned false');

      // Push updates: a new PlayerState arrives on track change, play/pause, seek.
      await _playerSub?.cancel();
      _playerSub = SpotifySdk.subscribePlayerState().listen(
        _onPlayerState,
        onError: (Object e) => debugPrint('PlayerState error: $e'),
      );
      // The position is NOT pushed every second: we advance it locally.
      _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted && _playerState != null) setState(() {});
      });

      setState(() {
        _remoteConnected = true;
        _status = 'Connected to the Spotify app';
      });
    } on SpotifyNotInstalledException {
      setState(() => _status = 'Error: the Spotify app is not installed');
    } on SpotifyException catch (e) {
      setState(() => _status = 'Spotify error: $e');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onPlayerState(PlayerState state) {
    _positionClock
      ..reset()
      ..start();
    final track = state.track;
    debugPrint(
      'PlayerState: ${track?.name} — ${track?.artist.name} | '
      'pos ${state.playbackPosition} ms / ${track?.duration} ms | '
      'paused ${state.isPaused} | shuffle ${state.playbackOptions.isShuffling}',
    );
    setState(() => _playerState = state);
  }

  /// Last received position + time elapsed since then (if playing).
  int get _livePositionMs {
    final state = _playerState;
    if (state == null) return 0;
    final elapsed = state.isPaused ? 0 : _positionClock.elapsedMilliseconds;
    final position = state.playbackPosition + elapsed;
    final duration = state.track?.duration ?? 0;
    return duration > 0 ? min(position, duration) : position;
  }

  Future<void> _playOnPhone() async {
    setState(() {
      _loading = true;
      _status = 'Starting playback on this phone...';
    });
    try {
      // App Remote controls the ACTIVE Spotify Connect device (it can be the PC).
      // First move playback to this phone, then play.
      await SpotifySdk.switchToLocalDevice();
      await SpotifySdk.play(spotifyUri: 'spotify:playlist:$mainPlaylistId');
      setState(() => _status = 'Playing main playlist on this phone');
    } on SpotifyException catch (e) {
      setState(() => _status = 'Spotify error: $e');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingConfig = clientId.isEmpty ||
        redirectUri.isEmpty ||
        mainPlaylistId.isEmpty ||
        (Platform.isAndroid && appRemoteRedirectUri.isEmpty);
    final nowPlaying = _playerState?.track;

    return Scaffold(
      appBar: AppBar(title: const Text('PlayTier — Spike')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (missingConfig)
              const Text(
                'Missing config: run with --dart-define-from-file=config.json',
                style: TextStyle(color: Colors.redAccent),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: const Text('Log in with Spotify'),
                ),
                FilledButton.tonal(
                  onPressed: _loading || _token == null ? null : _loadPlaylist,
                  child: const Text('Load main playlist'),
                ),
                FilledButton.tonal(
                  onPressed: _loading || _token == null ? null : _loadDevices,
                  child: const Text('List devices'),
                ),
                FilledButton.icon(
                  onPressed: _loading || _selectedDeviceId == null
                      ? null
                      : _playMainPlaylist,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play main playlist'),
                ),
                FilledButton.tonal(
                  onPressed: _loading ||
                          _selectedDeviceId == null ||
                          _tracks.isEmpty
                      ? null
                      : _writeAndPlayInOrder,
                  child: const Text('Write & play in order'),
                ),
                FilledButton.tonal(
                  onPressed:
                      _loading || _writtenUris == null ? null : _nextAndCheck,
                  child: const Text('Next & check'),
                ),
                if (Platform.isAndroid) ...[
                  FilledButton.tonal(
                    onPressed: _loading ? null : _authorizeAppRemote,
                    child: Text(
                      _remoteAuthorized ? 'Authorized ✓' : 'Authorize App Remote',
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed:
                        _loading || _remoteConnected ? null : _connectAppRemote,
                    child: const Text('Connect App Remote'),
                  ),
                  FilledButton.icon(
                    onPressed: _loading || !_remoteConnected ? null : _playOnPhone,
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Play on this phone'),
                  ),
                ],
              ],
            ),
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Tap a device to choose where to play.
              Wrap(
                spacing: 8,
                children: [
                  for (final device in _devices)
                    ChoiceChip(
                      label: Text('${device.name} (${device.type})'),
                      selected: device.id == _selectedDeviceId,
                      onSelected: device.id == null || device.isRestricted
                          ? null
                          : (_) => setState(() => _selectedDeviceId = device.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SelectableText(_status, textAlign: TextAlign.center),
            if (nowPlaying != null) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    _playerState!.isPaused ? Icons.pause : Icons.play_arrow,
                  ),
                  title: Text(nowPlaying.name),
                  subtitle: Text(
                    '${nowPlaying.artist.name ?? '?'}\n'
                    '${_formatMs(_livePositionMs)} / '
                    '${_formatMs(nowPlaying.duration)}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_writtenUris != null) _buildChunkHeader(),
            Expanded(
              child: _writtenUris == null
                  ? _buildMainPreview()
                  : _buildWrittenChunk(),
            ),
          ],
        ),
      ),
    );
  }

  /// Before writing: first 20 tracks of the main playlist.
  Widget _buildMainPreview() {
    return ListView.builder(
      itemCount: min(_tracks.length, 20),
      itemBuilder: (context, i) {
        final track = _tracks[i];
        return ListTile(
          dense: true,
          leading: Text('${i + 1}'),
          title: Text(track.name),
          subtitle: Text(
            '${track.artists.join(', ')} · added ${track.addedAtLabel}',
          ),
        );
      },
    );
  }

  /// "Chunk 1 of 2 (1–100 of 123)" with previous / next buttons.
  Widget _buildChunkHeader() {
    final total = _writtenUris!.length;
    final chunkCount = (total / 100).ceil();
    final first = _previewChunk * 100 + 1;
    final last = min(first + 99, total);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous chunk',
          onPressed: _previewChunk > 0
              ? () => setState(() => _previewChunk--)
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Chunk ${_previewChunk + 1} of $chunkCount  ($first–$last of $total)'),
        IconButton(
          tooltip: 'Next chunk',
          onPressed: _previewChunk < chunkCount - 1
              ? () => setState(() => _previewChunk++)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  /// After writing: the tracks of the selected chunk, in the written order.
  /// The track that should be playing now is highlighted.
  Widget _buildWrittenChunk() {
    final start = _previewChunk * 100;
    final end = min(start + 100, _writtenUris!.length);
    return ListView.builder(
      itemCount: end - start,
      itemBuilder: (context, i) {
        final index = start + i;
        final track = _trackByUri[_writtenUris![index]];
        return ListTile(
          dense: true,
          selected: index == _expectedIndex,
          leading: Text('${index + 1}'),
          title: Text(track?.name ?? _writtenUris![index]),
          subtitle: Text(track?.artists.join(', ') ?? ''),
          trailing: index == _expectedIndex ? const Icon(Icons.volume_up) : null,
        );
      },
    );
  }
}

String _formatMs(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Main playlist (GET /playlists/{id}/items)
// ---------------------------------------------------------------------------

/// Minimal track model for the spike (the real one comes in v0.1).
class SpikeTrack {
  const SpikeTrack({
    required this.name,
    required this.artists,
    required this.addedAt,
    required this.uri,
    required this.isLocal,
    required this.isPlayable,
  });

  final String name;
  final List<String> artists;
  final DateTime? addedAt;
  final String? uri;
  final bool isLocal;

  /// false if Spotify cannot play it in the user's country (hidden in the app).
  final bool isPlayable;

  /// Builds a track from one entry of `items[]`.
  factory SpikeTrack.fromJson(Map<String, dynamic> entry) {
    final item = entry['item'] as Map<String, dynamic>;
    final artists = (item['artists'] as List? ?? [])
        .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '?')
        .toList();
    final addedAt = entry['added_at'] as String?;
    return SpikeTrack(
      name: item['name'] as String? ?? '(no name)',
      artists: artists,
      addedAt: addedAt == null ? null : DateTime.parse(addedAt),
      uri: item['uri'] as String?,
      isLocal: entry['is_local'] as bool? ?? false,
      isPlayable: item['is_playable'] as bool? ?? true,
    );
  }

  String get addedAtLabel =>
      addedAt == null ? 'unknown' : addedAt!.toLocal().toString().substring(0, 16);

  @override
  String toString() =>
      '$name — ${artists.join(', ')} (added $addedAtLabel)'
      '${isLocal ? ' [local]' : ''}${isPlayable ? '' : ' [not playable]'}';
}

/// Reads ALL tracks of a playlist following the `next` link (50 per page).
Future<List<SpikeTrack>> fetchPlaylistTracks(String token, String playlistId) async {
  final tracks = <SpikeTrack>[];
  Uri? url = Uri.https('api.spotify.com', '/v1/playlists/$playlistId/items', {
    'limit': '50',
    // Only the fields we need: smaller and faster responses.
    // market=from_token → Spotify adds `is_playable` for the user's country.
    'market': 'from_token',
    'fields': 'next,total,items(added_at,is_local,item(type,id,name,uri,is_playable,artists(name)))',
  });
  var page = 0;

  while (url != null) {
    final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});

    if (res.statusCode == 429) {
      // Rate limit: wait the seconds Spotify asks for and retry the same page.
      final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 1;
      debugPrint('429 received, waiting $wait s');
      await Future.delayed(Duration(seconds: wait));
      continue;
    }
    if (res.statusCode != 200) {
      throw Exception('Playlist error ${res.statusCode}: ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = body['items'] as List;
    page++;
    debugPrint('Page $page: ${items.length} items (total ${body['total']})');

    for (final entry in items.cast<Map<String, dynamic>>()) {
      final item = entry['item'] as Map<String, dynamic>?;
      // Skip unavailable tracks (item == null) and podcast episodes.
      if (item == null || item['type'] != 'track') continue;
      tracks.add(SpikeTrack.fromJson(entry));
    }

    final next = body['next'] as String?;
    url = next == null ? null : Uri.parse(next);
  }
  return tracks;
}

// ---------------------------------------------------------------------------
// Playback on Spotify Connect devices (desktop)
// ---------------------------------------------------------------------------

/// Minimal device model for the spike.
class SpikeDevice {
  const SpikeDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.isRestricted,
  });

  final String? id;
  final String name;
  final String type;
  final bool isActive;
  final bool isRestricted;

  factory SpikeDevice.fromJson(Map<String, dynamic> json) => SpikeDevice(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '(no name)',
        type: json['type'] as String? ?? 'Unknown',
        isActive: json['is_active'] as bool? ?? false,
        isRestricted: json['is_restricted'] as bool? ?? false,
      );

  @override
  String toString() => '$name [$type] id=$id'
      '${isActive ? ' (active)' : ''}${isRestricted ? ' (restricted)' : ''}';
}

/// GET /me/player/devices — devices where the user can play right now.
Future<List<SpikeDevice>> fetchDevices(String token) async {
  final res = await http.get(
    Uri.https('api.spotify.com', '/v1/me/player/devices'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('Devices error ${res.statusCode}: ${res.body}');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return (body['devices'] as List)
      .cast<Map<String, dynamic>>()
      .map(SpikeDevice.fromJson)
      .toList();
}

/// PUT /me/player — transfers playback to a device (play: false = keep paused).
Future<void> transferPlayback(
  String token, {
  required String deviceId,
  bool play = false,
}) async {
  final res = await http.put(
    Uri.https('api.spotify.com', '/v1/me/player'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'device_ids': [deviceId],
      'play': play,
    }),
  );
  if (res.statusCode >= 300) {
    throw Exception('Transfer error ${res.statusCode}: ${res.body}');
  }
}

/// PUT /me/player/play — plays a context (playlist/album) on a device.
Future<void> startPlayback(
  String token, {
  required String deviceId,
  required String contextUri,
  int? offsetPosition,
}) async {
  final res = await http.put(
    Uri.https('api.spotify.com', '/v1/me/player/play', {'device_id': deviceId}),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'context_uri': contextUri,
      if (offsetPosition != null) 'offset': {'position': offsetPosition},
    }),
  );
  // 204 = playback started. Some clients answer 200/202.
  if (res.statusCode >= 300) {
    throw Exception('Play error ${res.statusCode}: ${res.body}');
  }
}

/// PUT /me/player/shuffle — turns shuffle on/off on a device.
Future<void> setShuffle(
  String token, {
  required String deviceId,
  required bool state,
}) async {
  final res = await http.put(
    Uri.https('api.spotify.com', '/v1/me/player/shuffle', {
      'state': '$state',
      'device_id': deviceId,
    }),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode >= 300) {
    throw Exception('Shuffle error ${res.statusCode}: ${res.body}');
  }
}

/// POST /me/player/next — skips to the next track.
Future<void> skipToNext(String token, {required String deviceId}) async {
  final res = await http.post(
    Uri.https('api.spotify.com', '/v1/me/player/next', {'device_id': deviceId}),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode >= 300) {
    throw Exception('Next error ${res.statusCode}: ${res.body}');
  }
}

/// GET /me/player — current playback state, or null if nothing is active.
Future<Map<String, dynamic>?> fetchPlaybackState(String token) async {
  final res = await http.get(
    Uri.https('api.spotify.com', '/v1/me/player'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode == 204) return null;
  if (res.statusCode != 200) {
    throw Exception('Player state error ${res.statusCode}: ${res.body}');
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

// ---------------------------------------------------------------------------
// Playback playlist (step 6)
// ---------------------------------------------------------------------------

/// Returns the id of the user's playlist called [name], creating it as a
/// private playlist if it does not exist (so we don't fill the library).
Future<String> findOrCreatePlaylist(String token, String name) async {
  final headers = {'Authorization': 'Bearer $token'};

  Uri? url = Uri.https('api.spotify.com', '/v1/me/playlists', {'limit': '50'});
  while (url != null) {
    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('My playlists error ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    for (final p in (body['items'] as List).whereType<Map<String, dynamic>>()) {
      if (p['name'] == name) {
        debugPrint('Reusing playlist "$name" (${p['id']})');
        return p['id'] as String;
      }
    }
    final next = body['next'] as String?;
    url = next == null ? null : Uri.parse(next);
  }

  final res = await http.post(
    Uri.https('api.spotify.com', '/v1/me/playlists'),
    headers: {...headers, 'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': name,
      'public': false,
      'description': 'Playback queue generated by PlayTier. Safe to ignore.',
    }),
  );
  if (res.statusCode != 201 && res.statusCode != 200) {
    throw Exception('Create playlist error ${res.statusCode}: ${res.body}');
  }
  final id = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  debugPrint('Created private playlist "$name" ($id)');
  return id;
}

/// Writes [uris] to the playlist in order, in chunks of 100:
/// the first chunk REPLACES all items (PUT), the rest are APPENDED (POST).
Future<void> replacePlaylistItems(
  String token,
  String playlistId,
  List<String> uris,
) async {
  final url = Uri.https('api.spotify.com', '/v1/playlists/$playlistId/items');
  final headers = {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  for (var start = 0; start < uris.length; start += 100) {
    final chunk = uris.sublist(start, min(start + 100, uris.length));
    final body = jsonEncode({'uris': chunk});
    final res = start == 0
        ? await http.put(url, headers: headers, body: body)
        : await http.post(url, headers: headers, body: body);
    debugPrint('Chunk ${start ~/ 100 + 1}: ${chunk.length} items -> HTTP ${res.statusCode}');
    if (res.statusCode >= 300) {
      throw Exception('Write items error ${res.statusCode}: ${res.body}');
    }
  }
}

// ---------------------------------------------------------------------------
// PKCE login flow
// ---------------------------------------------------------------------------

/// PKCE login: opens Spotify in the browser, waits for the redirect
/// (local server on desktop, deep link on Android) and exchanges the code.
Future<String> loginWithSpotify() async {
  final verifier = _randomString(64);
  final state = _randomString(16);

  final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
    'client_id': clientId,
    'response_type': 'code',
    'redirect_uri': redirectUri,
    'code_challenge_method': 'S256',
    'code_challenge': _codeChallenge(verifier),
    'state': state,
    'scope': scopes.join(' '),
  });

  final params = Platform.isAndroid
      ? await _waitForAndroidRedirect(authUrl)
      : await _waitForDesktopRedirect(authUrl);

  if (params['state'] != state) throw Exception('State mismatch');
  final code = params['code'];
  if (code == null) throw Exception('Login error: ${params['error']}');

  // Exchange the code for tokens (no client secret thanks to PKCE).
  final res = await http.post(
    Uri.https('accounts.spotify.com', '/api/token'),
    body: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': verifier,
    },
  );
  if (res.statusCode != 200) {
    throw Exception('Token error ${res.statusCode}: ${res.body}');
  }
  return (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;
}

/// Desktop: receives http://127.0.0.1:PORT/callback on a local server.
Future<Map<String, String>> _waitForDesktopRedirect(Uri authUrl) async {
  final redirect = Uri.parse(redirectUri);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, redirect.port);
  try {
    await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    final request = await server.firstWhere((r) => r.uri.path == redirect.path);
    request.response
      ..headers.contentType = ContentType.html
      ..write('<h2>PlayTier: login complete. You can close this tab.</h2>');
    await request.response.close();
    return request.uri.queryParameters;
  } finally {
    await server.close(force: true);
  }
}

/// Android: receives playtier://callback?code=... as a deep link.
Future<Map<String, String>> _waitForAndroidRedirect(Uri authUrl) async {
  final appLinks = AppLinks();
  // Start listening BEFORE opening the browser so the redirect is not missed.
  final redirectFuture = appLinks.uriLinkStream.firstWhere(
    (uri) => uri.scheme == 'playtier' && uri.host == 'callback',
  );
  await launchUrl(authUrl, mode: LaunchMode.externalApplication);
  final uri = await redirectFuture.timeout(const Duration(minutes: 5));
  return uri.queryParameters;
}

String _randomString(int length) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final random = Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
}

String _codeChallenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}