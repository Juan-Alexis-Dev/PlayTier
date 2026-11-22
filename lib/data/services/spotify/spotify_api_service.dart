import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dto/spotify_playlist_dto.dart';
import 'spotify_api_exception.dart';

/// Spotify Web API calls. Grows in v0.1 step 9 (playlist items, artists).
class SpotifyApiService {
  SpotifyApiService(this._client);

  /// Normally a `SpotifyHttpClient` (auth, refresh, backoff).
  final http.Client _client;

  static const _baseUrl = 'https://api.spotify.com/v1';

  /// Id of the logged-in user (`GET /me`).
  Future<String> getCurrentUserId() async {
    final json = await _getJson(Uri.parse('$_baseUrl/me'));
    return json['id'] as String;
  }

  /// All playlists the user owns or follows, following pagination.
  Future<List<SpotifyPlaylistDto>> getMyPlaylists() async {
    final playlists = <SpotifyPlaylistDto>[];
    Uri? next = Uri.parse('$_baseUrl/me/playlists?limit=50');

    while (next != null) {
      final json = await _getJson(next);
      for (final item in json['items'] as List<dynamic>) {
        if (item is Map<String, dynamic>) {
          playlists.add(SpotifyPlaylistDto.fromJson(item));
        }
      }
      final nextUrl = json['next'] as String?;
      next = nextUrl == null ? null : Uri.parse(nextUrl);
    }
    return playlists;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw SpotifyApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}