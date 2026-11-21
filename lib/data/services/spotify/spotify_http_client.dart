import 'dart:math';

import 'package:http/http.dart' as http;

/// HTTP client for the Spotify Web API.
///
/// - Adds `Authorization: Bearer <token>` to every request.
/// - On `401`, refreshes the token once and retries.
/// - On `429`, waits (`Retry-After` or exponential backoff) and retries up
///   to [maxRetries] times.
///
/// Tokens come from callbacks (normally `AuthRepository`), so this class
/// does not depend on the repository layer.
class SpotifyHttpClient extends http.BaseClient {
  SpotifyHttpClient({
    required this._getAccessToken,
    required this._refreshAccessToken,
    http.Client? inner,
    this.maxRetries = 3,
    Future<void> Function(Duration)? delay,
  })  : _inner = inner ?? http.Client(),
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  final Future<String?> Function() _getAccessToken;
  final Future<String?> Function() _refreshAccessToken;
  final http.Client _inner;
  final Future<void> Function(Duration) _delay;

  /// Maximum retries after a `429` response.
  final int maxRetries;

  static const _maxWait = Duration(seconds: 60);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      // Only simple requests can be copied for a retry.
      throw ArgumentError('SpotifyHttpClient only supports http.Request');
    }

    var token = await _getAccessToken();
    var refreshed = false;
    var retries = 0;

    while (true) {
      final response = await _inner.send(_copy(request, token));

      if (response.statusCode == 401 && !refreshed) {
        refreshed = true;
        final newToken = await _refreshAccessToken();
        if (newToken == null) return response; // Session lost.
        await response.stream.drain<void>();
        token = newToken;
        continue;
      }

      if (response.statusCode == 429 && retries < maxRetries) {
        final wait = _retryAfter(response) ?? Duration(seconds: 1 << retries);
        await response.stream.drain<void>();
        retries++;
        await _delay(wait > _maxWait ? _maxWait : wait);
        continue;
      }

      return response;
    }
  }

  @override
  void close() => _inner.close();

  static http.Request _copy(http.Request original, String? token) {
    final copy = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..encoding = original.encoding
      ..bodyBytes = original.bodyBytes
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    if (token != null) copy.headers['Authorization'] = 'Bearer $token';
    return copy;
  }

  static Duration? _retryAfter(http.StreamedResponse response) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    return seconds == null ? null : Duration(seconds: max(seconds, 1));
  }
}