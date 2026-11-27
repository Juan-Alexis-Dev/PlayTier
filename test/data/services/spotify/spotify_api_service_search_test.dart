import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';

Map<String, dynamic> track(String id, {Map<String, dynamic>? extra}) => {
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
    };

/// Fake API that records requests and answers with [items].
({SpotifyApiService api, List<http.Request> requests}) fakeApi(
  List<Map<String, dynamic>> items, {
  int status = 200,
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    if (status != 200) return http.Response('{"error":{}}', status);
    return http.Response(
      jsonEncode({
        'tracks': {'items': items, 'next': null},
      }),
      200,
    );
  });
  return (api: SpotifyApiService(client), requests: requests);
}

void main() {
  test('searchTracks sends the query and parses tracks', () async {
    final fake = fakeApi([track('t1'), track('t2')]);

    final tracks = await fake.api.searchTracks('muse uprising');

    final url = fake.requests.single.url;
    expect(url.path, '/v1/search');
    expect(url.queryParameters, {
      'q': 'muse uprising',
      'type': 'track',
      'market': 'from_token',
      'limit': '10',
      'offset': '0',
    });
    expect(tracks.map((t) => t.id), ['t1', 't2']);
    expect(tracks.first.artists.single.name, 'Artist 1');
    expect(tracks.first.coverUrl, 'https://img/1');
    expect(tracks.first.addedAt, isNull);
  });

  test('limit is clamped to the Dev Mode maximum', () async {
    final fake = fakeApi([]);
    await fake.api.searchTracks('x', limit: 50, offset: 20);

    final query = fake.requests.single.url.queryParameters;
    expect(query['limit'], '${SpotifyApiService.searchLimit}');
    expect(query['offset'], '20');
  });

  test('skips unplayable and local tracks', () async {
    final fake = fakeApi([
      track('t1'),
      track('t2', extra: {'is_playable': false}),
      track('t3', extra: {'is_local': true}),
    ]);
    final tracks = await fake.api.searchTracks('x');
    expect(tracks.map((t) => t.id), ['t1']);
  });

  test('errors throw SpotifyApiException', () async {
    final fake = fakeApi([], status: 401);
    await expectLater(
      fake.api.searchTracks('x'),
      throwsA(isA<SpotifyApiException>()),
    );
  });
}