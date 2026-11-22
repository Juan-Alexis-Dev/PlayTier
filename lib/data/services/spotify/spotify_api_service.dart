import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dto/spotify_artist_dto.dart';
import 'dto/spotify_playlist_dto.dart';
import 'dto/spotify_playlist_item_dto.dart';
import 'spotify_api_exception.dart';

/// Spotify Web API calls.
///
/// Uses the February 2026 Development Mode endpoints: `/playlists/{id}/items`
/// (not `/tracks`) and `/artists/{id}` (the batch `/artists` was removed).
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
    await _forEachPage(Uri.parse('$_baseUrl/me/playlists?limit=50'), (item) {
      playlists.add(SpotifyPlaylistDto.fromJson(item));
    });
    return playlists;
  }

  /// Current `snapshot_id` of a playlist (changes on every edit).
  Future<String> getPlaylistSnapshotId(String playlistId) async {
    final json = await _getJson(
      Uri.parse('$_baseUrl/playlists/$playlistId')
          .replace(queryParameters: {'fields': 'snapshot_id'}),
    );
    return json['snapshot_id'] as String;
  }

  /// Playable tracks of a playlist, in playlist order.
  ///
  /// Local files, episodes and unplayable tracks are skipped.
  Future<List<SpotifyPlaylistItemDto>> getPlaylistItems(
    String playlistId,
  ) async {
    final tracks = <SpotifyPlaylistItemDto>[];
    final firstPage = Uri.parse('$_baseUrl/playlists/$playlistId/items')
        .replace(queryParameters: {'market': 'from_token', 'limit': '50'});
    await _forEachPage(firstPage, (item) {
      final track = SpotifyPlaylistItemDto.tryParse(item);
      if (track != null) tracks.add(track);
    });
    return tracks;
  }

  /// One artist with its genres (used by genre enrichment in v0.4).
  Future<SpotifyArtistDto> getArtist(String artistId) async {
    final json = await _getJson(Uri.parse('$_baseUrl/artists/$artistId'));
    return SpotifyArtistDto.fromJson(json);
  }

  /// Calls [onItem] for every object in `items`, following `next` links.
  Future<void> _forEachPage(
    Uri firstPage,
    void Function(Map<String, dynamic> item) onItem,
  ) async {
    Uri? next = firstPage;
    while (next != null) {
      final json = await _getJson(next);
      for (final item in json['items'] as List<dynamic>? ?? const []) {
        if (item is Map<String, dynamic>) onItem(item);
      }
      final nextUrl = json['next'] as String?;
      next = nextUrl == null ? null : Uri.parse(nextUrl);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw SpotifyApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}