import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lastfm_api_exception.dart';

/// A Last.fm tag with its relative weight (0–100, highest first).
typedef LastFmTag = ({String name, int count});

/// Last.fm API calls.
///
/// v0.4 only needs artist tags (genre enrichment, FR-2.5); top tracks,
/// similar and charts are added in v0.6 (Discover).
class LastFmService {
  LastFmService(this._client, {required this._apiKey});

  final http.Client _client;
  final String _apiKey;

  static const _baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const userAgent =
      'PlayTier/0.4 ( https://github.com/Juan-Alexis-Dev/PlayTier )';

  /// Last.fm error code for "artist/track not found".
  static const _errorNotFound = 6;

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
    final topTags = json?['toptags'];
    if (topTags is! Map<String, dynamic>) return const [];

    return [
      for (final tag in _asList(topTags['tag']))
        if (tag is Map<String, dynamic> && tag['name'] is String)
          (name: tag['name'] as String, count: _toInt(tag['count'])),
    ];
  }

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