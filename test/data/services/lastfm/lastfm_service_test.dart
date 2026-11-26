import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/lastfm/lastfm_api_exception.dart';
import 'package:playtier/data/services/lastfm/lastfm_service.dart';

/// Records every request and answers with [body] and [status].
({LastFmService api, List<http.Request> requests}) fakeApi(
  Object body, {
  int status = 200,
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
    );
  });
  return (api: LastFmService(client, apiKey: 'key123'), requests: requests);
}

Map<String, dynamic> topTags(Object tag) => {
      'toptags': {
        'tag': tag,
        '@attr': {'artist': 'Muse'},
      },
    };

void main() {
  group('getArtistTopTags', () {
    test('sends method, artist, key, format and User-Agent', () async {
      final fake = fakeApi(topTags([]));
      await fake.api.getArtistTopTags('Café Tacvba');

      final request = fake.requests.single;
      expect(request.url.host, 'ws.audioscrobbler.com');
      expect(request.url.path, '/2.0/');
      expect(request.url.queryParameters, {
        'method': 'artist.gettoptags',
        'artist': 'Café Tacvba',
        'autocorrect': '1',
        'api_key': 'key123',
        'format': 'json',
      });
      expect(request.headers['User-Agent'], LastFmService.userAgent);
    });

    test('parses tags in order with their counts', () async {
      final fake = fakeApi(topTags([
        {'name': 'alternative rock', 'count': 100, 'url': 'u'},
        {'name': 'rock', 'count': '87', 'url': 'u'},
        {'name': 'seen live', 'count': 5, 'url': 'u'},
      ]));

      expect(await fake.api.getArtistTopTags('Muse'), [
        (name: 'alternative rock', count: 100),
        (name: 'rock', count: 87),
        (name: 'seen live', count: 5),
      ]);
    });

    test('a single tag object becomes a list of one', () async {
      final fake = fakeApi(topTags({'name': 'rock', 'count': 100}));
      expect(await fake.api.getArtistTopTags('Muse'), [
        (name: 'rock', count: 100),
      ]);
    });

    test('no tags returns an empty list', () async {
      final fake = fakeApi(topTags([]));
      expect(await fake.api.getArtistTopTags('Muse'), isEmpty);
    });

    test('unknown artist (error 6) returns an empty list', () async {
      final fake = fakeApi(
        {'error': 6, 'message': 'The artist you supplied could not be found'},
        status: 404,
      );
      expect(await fake.api.getArtistTopTags('zzzz'), isEmpty);
    });

    test('rate limit (error 29) throws with the Last.fm code', () async {
      final fake = fakeApi(
        {'error': 29, 'message': 'Rate limit exceeded'},
        status: 429,
      );
      expect(
        fake.api.getArtistTopTags('Muse'),
        throwsA(isA<LastFmApiException>()
            .having((e) => e.errorCode, 'errorCode', 29)
            .having((e) => e.statusCode, 'statusCode', 429)),
      );
    });

    test('a non-JSON server error throws with the status code', () async {
      final fake = fakeApi('<html>Bad Gateway</html>', status: 502);
      expect(
        fake.api.getArtistTopTags('Muse'),
        throwsA(isA<LastFmApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.errorCode, 'errorCode', isNull)),
      );
    });
  });
}