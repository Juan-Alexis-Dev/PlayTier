import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/config.dart';
import 'dto/spotify_tokens.dart';
import 'spotify_auth_exception.dart';

/// Spotify OAuth 2.0 Authorization Code flow with PKCE.
///
/// - Desktop (Linux/Windows): local loopback server receives the redirect.
/// - Android: custom scheme redirect received with `app_links`.
class SpotifyAuthService {
  SpotifyAuthService(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final AppConfig _config;
  final http.Client _client;

  static final _tokenUri = Uri.parse('https://accounts.spotify.com/api/token');
  static const _loginTimeout = Duration(minutes: 5);
  static const _verifierChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Permissions requested at login.
  static const scopes = [
    'user-read-private',
    'playlist-read-private',
    'playlist-read-collaborative',
    'playlist-modify-private',
    'playlist-modify-public',
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
  ];

  /// Opens the browser, waits for the redirect and exchanges the code.
  Future<SpotifyTokens> login() async {
    final verifier = _randomString(64);
    final state = _randomString(16);
    final redirectUri = _config.spotifyRedirectUri;

    final authorizeUri = Uri.https('accounts.spotify.com', '/authorize', {
      'response_type': 'code',
      'client_id': _config.spotifyClientId,
      'scope': scopes.join(' '),
      'redirect_uri': redirectUri,
      'state': state,
      'code_challenge_method': 'S256',
      'code_challenge': _codeChallenge(verifier),
    });

    final callback = Platform.isAndroid
        ? await _waitForAppLink(authorizeUri, redirectUri)
        : await _waitForLoopback(authorizeUri, redirectUri);

    final params = callback.queryParameters;
    final error = params['error'];
    if (error != null) {
      throw SpotifyAuthException('Login denied or cancelled', code: error);
    }
    if (params['state'] != state) {
      throw const SpotifyAuthException('State mismatch in login redirect');
    }
    final code = params['code'];
    if (code == null) {
      throw const SpotifyAuthException('No code in login redirect');
    }

    return _requestTokens({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': _config.spotifyClientId,
      'code_verifier': verifier,
    });
  }

  /// Gets a new access token. Spotify may also rotate the refresh token.
  Future<SpotifyTokens> refresh(String refreshToken) {
    return _requestTokens(
      {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': _config.spotifyClientId,
      },
      previousRefreshToken: refreshToken,
    );
  }

  Future<SpotifyTokens> _requestTokens(
    Map<String, String> body, {
    String? previousRefreshToken,
  }) async {
    // A Map body is sent as application/x-www-form-urlencoded.
    final response = await _client.post(_tokenUri, body: body);

    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw SpotifyAuthException('Invalid token response '
          '(HTTP ${response.statusCode})');
    }

    if (response.statusCode != 200) {
      throw SpotifyAuthException(
        json['error_description'] as String? ??
            'Token request failed (HTTP ${response.statusCode})',
        code: json['error'] as String?,
      );
    }
    return SpotifyTokens.fromTokenResponse(
      json,
      previousRefreshToken: previousRefreshToken,
    );
  }

  /// Desktop: listens on the loopback redirect URI.
  Future<Uri> _waitForLoopback(Uri authorizeUri, String redirectUri) async {
    final redirect = Uri.parse(redirectUri);
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, redirect.port);
    try {
      await _openBrowser(authorizeUri);
      final request = await server
          .firstWhere((r) => r.uri.path == redirect.path)
          .timeout(_loginTimeout);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('<html><body style="font-family:sans-serif">'
            '<h3>PlayTier: login finished.</h3>'
            '<p>You can close this window.</p></body></html>');
      await request.response.close();
      return request.uri;
    } finally {
      await server.close(force: true);
    }
  }

  /// Android: waits for the custom scheme redirect.
  Future<Uri> _waitForAppLink(Uri authorizeUri, String redirectUri) async {
    final redirect = Uri.parse(redirectUri);
    // Listen before opening the browser so the link is never missed.
    final link = AppLinks()
        .uriLinkStream
        .firstWhere(
          (uri) => uri.scheme == redirect.scheme && uri.host == redirect.host,
        )
        .timeout(_loginTimeout);
    try {
      await _openBrowser(authorizeUri);
    } catch (_) {
      link.ignore();
      rethrow;
    }
    return link;
  }

  Future<void> _openBrowser(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw const SpotifyAuthException('Could not open the browser');
    }
  }

  static String _randomString(int length) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => _verifierChars[random.nextInt(_verifierChars.length)],
    ).join();
  }

  static String _codeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}