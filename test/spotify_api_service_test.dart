import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';

Map<String, dynamic> trackItem(String id, {Map<String, dynamic>? extra}) => {
      'added_at': '2026-01-02T03:04:05Z',
      'is_local': false,
      'item': {
        'type': 'track',
        'id': id,
        'uri': 'spotify:track:$id',
        'name': 'Song $id',
        'duration_ms': 200000,
        'is_playable': true,
        'artists': [
          {'id': 'a1', 'name': 'Artist 1'},
        ],
        'album': {
          'id': 'al1',
          'name': 'Album',
          'release_date': '2020-05',
          'images': [
            {'url': 'https://img/1'},
          ],
        },
        ...?extra,
      },
    };

void main() {
  test('getPlaylistItems follows pages and skips ignored items', () async {
    const page2 = 'https://api.spotify.com/v1/playlists/p1/items?offset=50';
    final client = MockClient((request) async {
      final isFirst = !request.url.queryParameters.containsKey('offset');
      final body = isFirst
          ? {
              'items': [
                trackItem('t1'),
                {'is_local': true, 'item': null},
                trackItem('t2', extra: {'is_playable': false}),
                trackItem('e1', extra: {'type': 'episode'}),
              ],
              'next': page2,
            }
          : {
              'items': [trackItem('t3')],
              'next': null,
            };
      return http.Response(jsonEncode(body), 200);
    });

    final tracks = await SpotifyApiService(client).getPlaylistItems('p1');

    expect(tracks.map((t) => t.id), ['t1', 't3']);
    final first = tracks.first;
    expect(first.artists.single.id, 'a1');
    expect(first.albumName, 'Album');
    expect(first.releaseDate, '2020-05');
    expect(first.coverUrl, 'https://img/1');
    expect(first.addedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
  });

  test('getPlaylistInfo reads snapshot, name and cover', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/playlists/p1');
      expect(request.url.queryParameters['fields'], contains('snapshot_id'));
      return http.Response(
        jsonEncode({
          'id': 'p1',
          'snapshot_id': 'snap-1',
          'name': 'All my music',
          'images': [
            {'url': 'https://img/p1'},
          ],
        }),
        200,
      );
    });

    final info = await SpotifyApiService(client).getPlaylistInfo('p1');

    expect(info.snapshotId, 'snap-1');
    expect(info.name, 'All my music');
    expect(info.imageUrl, 'https://img/p1');
  });

  test('non-200 responses throw', () async {
    final client = MockClient((_) async => http.Response('nope', 403));

    expect(
      () => SpotifyApiService(client).getPlaylistInfo('p1'),
      throwsException,
    );
  });
}