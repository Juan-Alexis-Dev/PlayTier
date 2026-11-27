import 'dart:convert';

import 'package:http/http.dart' as http;

import 'musicbrainz_api_exception.dart';

/// A MusicBrainz genre with its number of votes.
typedef MusicBrainzGenre = ({String name, int count});

/// MusicBrainz API calls (genre fallback, FR-2.5).
///
/// No auth, but MusicBrainz requires a descriptive User-Agent and at most
/// one request per second. Requests are queued and spaced by [minInterval].
/// A `503` (server busy / rate limited) is retried up to [maxRetries]
/// times, waiting `Retry-After` or an exponential backoff.
class MusicBrainzService {
  MusicBrainzService(
    this._client, {
    this.minInterval = const Duration(milliseconds: 1100),
    this.retryBaseDelay = const Duration(seconds: 2),
    this.maxRetries = 3,
  });

  final http.Client _client;

  /// Minimum time between two requests. Tests pass `Duration.zero`.
  final Duration minInterval;

  /// First wait after a `503` without `Retry-After`; doubles each retry.
  final Duration retryBaseDelay;

  final int maxRetries;

  static const _baseUrl = 'https://musicbrainz.org/ws/2';
  static const userAgent =
      'PlayTier/0.4 ( https://github.com/Juan-Alexis-Dev/PlayTier )';

  Future<void> _queue = Future.value();
  DateTime? _lastRequestAt;

  /// MusicBrainz id of the artist linked to a Spotify artist, or null.
  ///
  /// Exact match through the Spotify URL stored in MusicBrainz.
  Future<String?> findArtistBySpotifyId(String spotifyArtistId) async {
    final json = await _getJson('/url', {
      'resource': 'https://open.spotify.com/artist/$spotifyArtistId',
      'inc': 'artist-rels',
    });
    for (final relation in _asList(json?['relations'])) {
      if (relation is! Map<String, dynamic>) continue;
      final artist = relation['artist'];
      if (artist is Map<String, dynamic> && artist['id'] is String) {
        return artist['id'] as String;
      }
    }
    return null;
  }

  /// MusicBrainz id of the best artist match for [name], or null when the
  /// best result scores below [minScore] (0–100).
  Future<String?> searchArtist(String name, {int minScore = 90}) async {
    final json = await _getJson('/artist', {
      'query': 'artist:"${_escape(name)}"',
      'limit': '1',
    });
    final artists = _asList(json?['artists']);
    if (artists.isEmpty) return null;
    final best = artists.first;
    if (best is! Map<String, dynamic> || best['id'] is! String) return null;
    final score = (best['score'] as num?)?.toInt() ?? 0;
    return score >= minScore ? best['id'] as String : null;
  }

  /// Genres of an artist, as MusicBrainz orders them.
  ///
  /// Returns an empty list when the id does not exist.
  Future<List<MusicBrainzGenre>> getArtistGenres(String musicBrainzId) async {
    final json = await _getJson('/artist/$musicBrainzId', {'inc': 'genres'});
    return [
      for (final genre in _asList(json?['genres']))
        if (genre is Map<String, dynamic> && genre['name'] is String)
          (
            name: genre['name'] as String,
            count: (genre['count'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  /// GET as JSON; null on 404.
  Future<Map<String, dynamic>?> _getJson(
    String path,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: {...params, 'fmt': 'json'});
    final response = await _throttledGet(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw MusicBrainzApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Runs requests one after another, at least [minInterval] apart.
  /// Retries stay inside the queue, so they also block the next request.
  Future<http.Response> _throttledGet(Uri uri) {
    final request = _queue.then((_) async {
      for (var retries = 0;; retries++) {
        await _waitForSlot();
        final response = await _client.get(uri, headers: {
          'User-Agent': userAgent,
          'Accept': 'application/json',
        });
        if (response.statusCode != 503 || retries >= maxRetries) {
          return response;
        }
        await Future<void>.delayed(
          _retryAfter(response) ?? retryBaseDelay * (1 << retries),
        );
      }
    });
    // Keep the queue alive even if this request fails.
    _queue = request.then((_) {}, onError: (Object _) {});
    return request;
  }

  Future<void> _waitForSlot() async {
    final last = _lastRequestAt;
    if (last != null) {
      final wait = minInterval - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequestAt = DateTime.now();
  }

  static Duration? _retryAfter(http.Response response) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}

List<Object?> _asList(Object? value) => value is List ? value : const [];

/// Escapes characters that break a quoted Lucene phrase.
String _escape(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');