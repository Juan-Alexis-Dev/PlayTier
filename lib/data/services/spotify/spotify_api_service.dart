import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dto/spotify_artist_dto.dart';
import 'dto/spotify_device_dto.dart';
import 'dto/spotify_player_dto.dart';
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

  /// Id, `snapshot_id`, name and cover of a playlist (one cheap call).
  Future<SpotifyPlaylistDto> getPlaylistInfo(String playlistId) async {
    final json = await _getJson(
      Uri.parse('$_baseUrl/playlists/$playlistId').replace(
        queryParameters: {'fields': 'id,snapshot_id,name,images'},
      ),
    );
    return SpotifyPlaylistDto.fromJson(json);
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

  // ---------------------------------------------------------------------
  // Player (Spotify Connect). All of them need Premium.
  // ---------------------------------------------------------------------

  /// Devices where Spotify is open (`GET /me/player/devices`).
  Future<List<SpotifyDeviceDto>> getDevices() async {
    final json = await _getJson(Uri.parse('$_baseUrl/me/player/devices'));
    return [
      for (final d in json['devices'] as List<dynamic>? ?? const [])
        if (d is Map<String, dynamic>) SpotifyDeviceDto.fromJson(d),
    ];
  }

  /// Current player state, or null when no device is active (`204`).
  Future<SpotifyPlayerDto?> getPlayer() async {
    final response = await _client.get(Uri.parse('$_baseUrl/me/player'));
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    if (response.statusCode != 200) {
      throw SpotifyApiException(response.statusCode, response.body);
    }
    return SpotifyPlayerDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Starts [contextUri] at [offsetPosition] on [deviceId]. Without
  /// [contextUri], resumes the current playback.
  Future<void> startPlayback({
    String? deviceId,
    String? contextUri,
    int offsetPosition = 0,
  }) {
    return _send(
      'PUT',
      _playerUri('play', {'device_id': ?deviceId}),
      body: contextUri == null
          ? null
          : {
              'context_uri': contextUri,
              'offset': {'position': offsetPosition},
            },
    );
  }

  Future<void> pausePlayback() => _send('PUT', _playerUri('pause'));

  Future<void> skipToNext() => _send('POST', _playerUri('next'));

  Future<void> skipToPrevious() => _send('POST', _playerUri('previous'));

  Future<void> seek(Duration position) => _send(
        'PUT',
        _playerUri('seek', {'position_ms': '${position.inMilliseconds}'}),
      );

  /// [state] is `off`, `context` or `track`.
  Future<void> setRepeat(String state) =>
      _send('PUT', _playerUri('repeat', {'state': state}));

  Future<void> setShuffle(bool state, {String? deviceId}) => _send(
        'PUT',
        _playerUri('shuffle', {'state': '$state', 'device_id': ?deviceId}),
      );

  Uri _playerUri(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('$_baseUrl/me/player/$path')
          .replace(queryParameters: query.isEmpty ? null : query);

  /// Sends a request whose success has no useful body (`200`/`202`/`204`).
  Future<void> _send(String method, Uri uri, {Object? body}) async {
    final response = switch (method) {
      'POST' => await _client.post(uri, headers: _jsonHeaders(body),
          body: body == null ? null : jsonEncode(body)),
      _ => await _client.put(uri, headers: _jsonHeaders(body),
          body: body == null ? null : jsonEncode(body)),
    };
    if (response.statusCode < 200 || response.statusCode > 204) {
      throw SpotifyApiException(response.statusCode, response.body);
    }
  }

  Map<String, String>? _jsonHeaders(Object? body) =>
      body == null ? null : const {'Content-Type': 'application/json'};

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