// SPIKE v0.0a — Steps 1–2: Spotify login with PKCE on desktop and Android.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PlayTier — Login spike')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (clientId.isEmpty || redirectUri.isEmpty)
                const Text(
                  'Missing config: run with --dart-define-from-file=config.json',
                  style: TextStyle(color: Colors.redAccent),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: const Text('Log in with Spotify'),
              ),
              const SizedBox(height: 24),
              SelectableText(_status, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
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