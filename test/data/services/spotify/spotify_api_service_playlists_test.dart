import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';

List<String> uris(int count) =>
    [for (var i = 0; i < count; i++) 'spotify:track:t$i'];

/// Records every request and answers with [status].
({SpotifyApiService api, List<http.Request> requests}) fakeApi({
  int status = 201,
  String body = '{"snapshot_id":"s1"}',
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response(body, status);
  });
  return (api: SpotifyApiService(client), requests: requests);
}

List<String> bodyUris(http.Request request) =>
    (jsonDecode(request.body)['uris'] as List).cast<String>();

void main() {
  group('replacePlaylistItems', () {
    test('first chunk replaces, the rest append, order kept', () async {
      final fake = fakeApi();
      final list = uris(250);
      await fake.api.replacePlaylistItems('p1', list);

      expect([for (final r in fake.requests) r.method], ['PUT', 'POST', 'POST']);
      expect(fake.requests.first.url.path, '/v1/playlists/p1/items');
      expect([for (final r in fake.requests) bodyUris(r).length], [100, 100, 50]);
      expect(
        [for (final r in fake.requests) ...bodyUris(r)],
        list,
      );
    });

    test('exactly 100 items is a single PUT', () async {
      final fake = fakeApi();
      await fake.api.replacePlaylistItems('p1', uris(100));
      expect(fake.requests.length, 1);
      expect(fake.requests.single.method, 'PUT');
    });

    test('an empty list empties the playlist', () async {
      final fake = fakeApi();
      await fake.api.replacePlaylistItems('p1', []);
      expect(fake.requests.single.method, 'PUT');
      expect(bodyUris(fake.requests.single), isEmpty);
    });

    test('duplicates are kept', () async {
      final fake = fakeApi();
      await fake.api.replacePlaylistItems('p1', ['a', 'b', 'a']);
      expect(bodyUris(fake.requests.single), ['a', 'b', 'a']);
    });

    test('errors throw SpotifyApiException', () async {
      final fake = fakeApi(status: 404, body: '{"error":{}}');
      await expectLater(
        fake.api.replacePlaylistItems('gone', ['a']),
        throwsA(
          isA<SpotifyApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });
  });

  test('addPlaylistItems only appends, in chunks', () async {
    final fake = fakeApi();
    await fake.api.addPlaylistItems('p1', uris(150));
    expect([for (final r in fake.requests) r.method], ['POST', 'POST']);
    expect(bodyUris(fake.requests.last).length, 50);
  });

  test('addPlaylistItems with no items sends nothing', () async {
    final fake = fakeApi();
    await fake.api.addPlaylistItems('p1', []);
    expect(fake.requests, isEmpty);
  });

  test('createPlaylist creates a private playlist', () async {
    final fake = fakeApi(
      body: jsonEncode({
        'id': 'new1',
        'name': 'Rock + Pop',
        'owner': {'id': 'me'},
      }),
    );
    final created = await fake.api.createPlaylist('Rock + Pop');

    final request = fake.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/me/playlists');
    expect(jsonDecode(request.body), {
      'name': 'Rock + Pop',
      'public': false,
      'description': '',
    });
    expect(created.id, 'new1');
  });
}