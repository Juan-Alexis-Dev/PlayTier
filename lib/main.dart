// SPIKE v0.0a — Step 1: Spotify login with PKCE on desktop (Linux/Windows).
// Throwaway code: lives only in the `spike/playback` branch.
//
// Run with:
//   flutter run -d linux --dart-define-from-file=config.json

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
const redirectUri = String.fromEnvironment('SPOTIFY_REDIRECT_URI_DESKTOP');

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

/// Opens the browser for Spotify login, receives the redirect on a local
/// server (127.0.0.1) and exchanges the code for an access token.
Future<String> loginWithSpotify() async {
  final verifier = _randomString(64);
  final state = _randomString(16);
  final redirect = Uri.parse(redirectUri);

  // 1. Local server that will receive the redirect from Spotify.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, redirect.port);

  try {
    // 2. Open the Spotify authorization page in the browser.
    final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': _codeChallenge(verifier),
      'state': state,
      'scope': scopes.join(' '),
    });
    await launchUrl(authUrl, mode: LaunchMode.externalApplication);

    // 3. Wait for Spotify to redirect to http://127.0.0.1:PORT/callback?code=...
    final request = await server.firstWhere((r) => r.uri.path == redirect.path);
    final params = request.uri.queryParameters;
    request.response
      ..headers.contentType = ContentType.html
      ..write('<h2>PlayTier: login complete. You can close this tab.</h2>');
    await request.response.close();

    if (params['state'] != state) throw Exception('State mismatch');
    final code = params['code'];
    if (code == null) throw Exception('Login error: ${params['error']}');

    // 4. Exchange the code for tokens (no client secret thanks to PKCE).
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
  } finally {
    await server.close(force: true);
  }
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
