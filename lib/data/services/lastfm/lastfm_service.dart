import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lastfm_api_exception.dart';

/// A Last.fm tag with its relative weight (0–100, highest first).
typedef LastFmTag = ({String name, int count});

/// A Last.fm track: only what is needed to match it on Spotify.
typedef LastFmTrack = ({String name, String artist});

/// A similar artist with its similarity to the source (0.0–1.0).
typedef LastFmSimilarArtist = ({String name, double match});

/// Last.fm API calls.
///
/// v0.4: artist tags (genre enrichment, FR-2.5).
/// v0.6: top tracks, similar artists/tracks/tags and charts (Discover,
/// FR-10). Every list keeps Last.fm's order (rank or match, best first).
class LastFmService {
  LastFmService(this._client, {required this._apiKey});

  final http.Client _client;
  final String _apiKey;

  static const _baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const userAgent =
      'PlayTier/0.6 ( https://github.com/Juan-Alexis-Dev/PlayTier )';

  /// Default page size for list methods.
  static const defaultLimit = 50;

  /// Last.fm error code for "artist/track/tag not found".
  static const _errorNotFound = 6;

  // ---------------------------------------------------------------- tags

  /// Top tags of an artist, highest weight first (`artist.getTopTags`).
  ///
  /// Returns an empty list when Last.fm does not know the artist.
  /// Tags are returned as Last.fm sends them; filtering and lower-casing
  /// are done by `GenreRepository`.
  Future<List<LastFmTag>> getArtistTopTags(String artistName) async {
    final json = await _call({
      'method': 'artist.gettoptags',
      'artist': artistName,
      'autocorrect': '1',
    });
    return [
      for (final tag in _items(json, 'toptags', 'tag'))
        if (tag['name'] is String)
          (name: tag['name'] as String, count: _toInt(tag['count'])),
    ];
  }

  /// Tags similar to [tag] (`tag.getSimilar`).
  ///
  /// Last.fm returns an empty list for many tags; callers must handle it.
  Future<List<String>> getSimilarTags(String tag) async {
    final json = await _call({'method': 'tag.getsimilar', 'tag': tag});
    return _names(_items(json, 'similartags', 'tag'));
  }

  // ---------------------------------------------------------- top tracks

  /// Most popular tracks of an artist (`artist.getTopTracks`, FR-10.1).
  Future<List<LastFmTrack>> getArtistTopTracks(
    String artistName, {
    int limit = defaultLimit,
  }) async {
    final json = await _call({
      'method': 'artist.gettoptracks',
      'artist': artistName,
      'autocorrect': '1',
      'limit': '$limit',
    });
    return _tracks(_items(json, 'toptracks', 'track'));
  }

  /// Most popular tracks of a tag/genre (`tag.getTopTracks`, FR-10.2).
  Future<List<LastFmTrack>> getTagTopTracks(
    String tag, {
    int limit = defaultLimit,
  }) async {
    final json = await _call({
      'method': 'tag.gettoptracks',
      'tag': tag,
      'limit': '$limit',
    });
    return _tracks(_items(json, 'tracks', 'track'));
  }

  // ------------------------------------------------------------- similar

  /// Artists similar to [artistName], most similar first
  /// (`artist.getSimilar`, FR-10.3).
  Future<List<LastFmSimilarArtist>> getSimilarArtists(
    String artistName, {
    int limit = defaultLimit,
  }) async {
    final json = await _call({
      'method': 'artist.getsimilar',
      'artist': artistName,
      'autocorrect': '1',
      'limit': '$limit',
    });
    return [
      for (final artist in _items(json, 'similarartists', 'artist'))
        if (artist['name'] is String)
          (name: artist['name'] as String, match: _toDouble(artist['match'])),
    ];
  }

  /// Tracks similar to a track, most similar first
  /// (`track.getSimilar`, FR-10.3).
  Future<List<LastFmTrack>> getSimilarTracks(
    String artistName,
    String trackName, {
    int limit = defaultLimit,
  }) async {
    final json = await _call({
      'method': 'track.getsimilar',
      'artist': artistName,
      'track': trackName,
      'autocorrect': '1',
      'limit': '$limit',
    });
    return _tracks(_items(json, 'similartracks', 'track'));
  }

  // -------------------------------------------------------------- charts

  /// Global top tracks (`chart.getTopTracks`, FR-10.4).
  Future<List<LastFmTrack>> getChartTopTracks({
    int limit = defaultLimit,
  }) async {
    final json =
        await _call({'method': 'chart.gettoptracks', 'limit': '$limit'});
    return _tracks(_items(json, 'tracks', 'track'));
  }

  /// Global top artist names (`chart.getTopArtists`, FR-10.4).
  Future<List<String>> getChartTopArtists({int limit = defaultLimit}) async {
    final json =
        await _call({'method': 'chart.gettopartists', 'limit': '$limit'});
    return _names(_items(json, 'artists', 'artist'));
  }

  /// Global top tag names (`chart.getTopTags`, FR-10.4).
  Future<List<String>> getChartTopTags({int limit = defaultLimit}) async {
    final json = await _call({'method': 'chart.gettoptags', 'limit': '$limit'});
    return _names(_items(json, 'tags', 'tag'));
  }

  // ------------------------------------------------------------- helpers

  /// Calls a method and returns the JSON body, or null for "not found".
  Future<Map<String, dynamic>?> _call(Map<String, String> params) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      ...params,
      'api_key': _apiKey,
      'format': 'json',
    });
    final response = await _client.get(uri, headers: {'User-Agent': userAgent});
    final body = _tryDecode(response.body);

    // Last.fm reports errors in the body ({"error": 6, "message": "..."}).
    if (body is Map<String, dynamic> && body['error'] != null) {
      final code = _toInt(body['error']);
      if (code == _errorNotFound) return null;
      throw LastFmApiException(
        response.statusCode,
        body['message'] as String? ?? '',
        errorCode: code,
      );
    }
    if (response.statusCode != 200 || body is! Map<String, dynamic>) {
      throw LastFmApiException(response.statusCode, response.body);
    }
    return body;
  }
}

/// Reads `json[outer][inner]` as a list of objects (empty if missing).
List<Map<String, dynamic>> _items(
  Map<String, dynamic>? json,
  String outer,
  String inner,
) {
  final container = json?[outer];
  if (container is! Map<String, dynamic>) return const [];
  return [
    for (final item in _asList(container[inner]))
      if (item is Map<String, dynamic>) item,
  ];
}

/// Tracks with a name and an artist; the artist may be an object
/// (`{"name": ...}`) or, in some methods, a plain string.
List<LastFmTrack> _tracks(List<Map<String, dynamic>> items) {
  final result = <LastFmTrack>[];
  for (final item in items) {
    final name = item['name'];
    final artistField = item['artist'];
    final artist = artistField is Map<String, dynamic>
        ? artistField['name']
        : artistField;
    if (name is String && artist is String) {
      result.add((name: name, artist: artist));
    }
  }
  return result;
}

List<String> _names(List<Map<String, dynamic>> items) => [
      for (final item in items)
        if (item['name'] is String) item['name'] as String,
    ];

Object? _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// Last.fm sends a single object instead of a list when there is one item.
List<Object?> _asList(Object? value) {
  if (value is List) return value;
  if (value == null) return const [];
  return [value];
}

/// Counts may come as numbers or strings.
int _toInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

/// Match values may come as numbers or strings.
double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}