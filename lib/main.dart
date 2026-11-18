// SPIKE v0.0a — Steps 1–4: PKCE login (desktop + Android), reading the main
// playlist with pagination, and playing it on a Spotify Connect device.
// Throwaway code: lives only in the `spike/playback` branch.
//
// Run with:
//   flutter run -d linux --dart-define-from-file=config.json
//   flutter run -d <android-device-id> --dart-define-from-file=config.json

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
const desktopRedirectUri = String.fromEnvironment('SPOTIFY_REDIRECT_URI_DESKTOP');
const androidRedirectUri = String.fromEnvironment('SPOTIFY_REDIRECT_URI_ANDROID');
const mainPlaylistId = String.fromEnvironment('SPOTIFY_MAIN_PLAYLIST_ID');

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
      setState(() {
        _tracks = tracks;
        _status = 'Loaded ${tracks.length} tracks '
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
      // Pre-select the active device, otherwise the first computer.
      final preferred = devices.where((d) => d.isActive).firstOrNull ??
          devices.where((d) => d.type == 'Computer').firstOrNull ??
          devices.firstOrNull;
      setState(() {
        _devices = devices;
        _selectedDeviceId = preferred?.id;
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

  @override
  Widget build(BuildContext context) {
    final missingConfig =
        clientId.isEmpty || redirectUri.isEmpty || mainPlaylistId.isEmpty;

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
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  });

  final String name;
  final List<String> artists;
  final DateTime? addedAt;
  final String? uri;
  final bool isLocal;

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
    );
  }

  String get addedAtLabel =>
      addedAt == null ? 'unknown' : addedAt!.toLocal().toString().substring(0, 16);

  @override
  String toString() =>
      '$name — ${artists.join(', ')} (added $addedAtLabel)${isLocal ? ' [local]' : ''}';
}

/// Reads ALL tracks of a playlist following the `next` link (50 per page).
Future<List<SpikeTrack>> fetchPlaylistTracks(String token, String playlistId) async {
  final tracks = <SpikeTrack>[];
  Uri? url = Uri.https('api.spotify.com', '/v1/playlists/$playlistId/items', {
    'limit': '50',
    // Only the fields we need: smaller and faster responses.
    'fields': 'next,total,items(added_at,is_local,item(type,id,name,uri,artists(name)))',
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

/// PUT /me/player/play — plays a context (playlist/album) on a device.
Future<void> startPlayback(
  String token, {
  required String deviceId,
  required String contextUri,
}) async {
  final res = await http.put(
    Uri.https('api.spotify.com', '/v1/me/player/play', {'device_id': deviceId}),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'context_uri': contextUri}),
  );
  // 204 = playback started. Some clients answer 200/202.
  if (res.statusCode >= 300) {
    throw Exception('Play error ${res.statusCode}: ${res.body}');
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