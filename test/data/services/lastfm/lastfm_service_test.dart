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

  group('top tracks', () {
    test('getArtistTopTracks sends artist, autocorrect and limit', () async {
      final fake = fakeApi({'toptracks': {'track': []}});
      await fake.api.getArtistTopTracks('Muse', limit: 10);

      expect(fake.requests.single.url.queryParameters, {
        'method': 'artist.gettoptracks',
        'artist': 'Muse',
        'autocorrect': '1',
        'limit': '10',
        'api_key': 'key123',
        'format': 'json',
      });
    });

    test('getArtistTopTracks parses name and artist in rank order', () async {
      final fake = fakeApi({
        'toptracks': {
          'track': [
            {
              'name': 'Uprising',
              'playcount': '1000',
              'artist': {'name': 'Muse', 'mbid': 'x'},
              '@attr': {'rank': '1'},
            },
            {
              'name': 'Hysteria',
              'artist': {'name': 'Muse'},
            },
            {'name': 'No artist'},
          ],
        },
      });

      expect(await fake.api.getArtistTopTracks('Muse'), [
        (name: 'Uprising', artist: 'Muse'),
        (name: 'Hysteria', artist: 'Muse'),
      ]);
    });

    test('getArtistTopTracks uses the default limit', () async {
      final fake = fakeApi({'toptracks': {'track': []}});
      await fake.api.getArtistTopTracks('Muse');
      expect(
        fake.requests.single.url.queryParameters['limit'],
        '${LastFmService.defaultLimit}',
      );
    });

    test('getTagTopTracks reads tracks.track', () async {
      final fake = fakeApi({
        'tracks': {
          'track': {
            'name': 'Song',
            'artist': {'name': 'Band'},
          },
        },
      });

      expect(await fake.api.getTagTopTracks('rock', limit: 5), [
        (name: 'Song', artist: 'Band'),
      ]);
      expect(fake.requests.single.url.queryParameters, containsPair(
        'method',
        'tag.gettoptracks',
      ));
      expect(fake.requests.single.url.queryParameters['tag'], 'rock');
    });

    test('unknown artist returns an empty list', () async {
      final fake = fakeApi({'error': 6, 'message': 'not found'}, status: 404);
      expect(await fake.api.getArtistTopTracks('zzzz'), isEmpty);
    });
  });

  group('similar', () {
    test('getSimilarArtists parses names and match (number or string)',
        () async {
      final fake = fakeApi({
        'similarartists': {
          'artist': [
            {'name': 'Radiohead', 'match': '1'},
            {'name': 'Placebo', 'match': 0.75},
          ],
        },
      });

      expect(await fake.api.getSimilarArtists('Muse', limit: 2), [
        (name: 'Radiohead', match: 1.0),
        (name: 'Placebo', match: 0.75),
      ]);
      expect(fake.requests.single.url.queryParameters, containsPair(
        'method',
        'artist.getsimilar',
      ));
    });

    test('getSimilarTracks sends artist and track', () async {
      final fake = fakeApi({
        'similartracks': {
          'track': [
            {
              'name': 'Paranoid Android',
              'match': 1.0,
              'artist': {'name': 'Radiohead'},
            },
          ],
        },
      });

      expect(await fake.api.getSimilarTracks('Muse', 'Starlight'), [
        (name: 'Paranoid Android', artist: 'Radiohead'),
      ]);
      final params = fake.requests.single.url.queryParameters;
      expect(params['method'], 'track.getsimilar');
      expect(params['artist'], 'Muse');
      expect(params['track'], 'Starlight');
      expect(params['autocorrect'], '1');
    });

    test('getSimilarTags returns names; empty when Last.fm has none',
        () async {
      final withTags = fakeApi({
        'similartags': {
          'tag': [
            {'name': 'indie rock', 'url': 'u'},
            {'name': 'britpop', 'url': 'u'},
          ],
        },
      });
      expect(
        await withTags.api.getSimilarTags('rock'),
        ['indie rock', 'britpop'],
      );

      final empty = fakeApi({
        'similartags': {
          'tag': [],
          '@attr': {'tag': 'rock'},
        },
      });
      expect(await empty.api.getSimilarTags('rock'), isEmpty);
    });
  });

  group('charts', () {
    test('getChartTopTracks parses tracks and sends the limit', () async {
      final fake = fakeApi({
        'tracks': {
          'track': [
            {
              'name': 'Hit',
              'playcount': '99',
              'artist': {'name': 'Star'},
            },
          ],
        },
      });

      expect(await fake.api.getChartTopTracks(limit: 20), [
        (name: 'Hit', artist: 'Star'),
      ]);
      expect(fake.requests.single.url.queryParameters, {
        'method': 'chart.gettoptracks',
        'limit': '20',
        'api_key': 'key123',
        'format': 'json',
      });
    });

    test('getChartTopArtists returns names in order', () async {
      final fake = fakeApi({
        'artists': {
          'artist': [
            {'name': 'A', 'playcount': '2'},
            {'name': 'B', 'playcount': '1'},
          ],
        },
      });
      expect(await fake.api.getChartTopArtists(), ['A', 'B']);
    });

    test('getChartTopTags returns names in order', () async {
      final fake = fakeApi({
        'tags': {
          'tag': [
            {'name': 'pop', 'reach': '100'},
            {'name': 'rock', 'reach': '90'},
          ],
        },
      });
      expect(await fake.api.getChartTopTags(limit: 2), ['pop', 'rock']);
    });

    test('chart errors throw LastFmApiException', () async {
      final fake = fakeApi({'error': 29, 'message': 'Rate limit'}, status: 429);
      expect(
        fake.api.getChartTopTags(),
        throwsA(isA<LastFmApiException>()
            .having((e) => e.errorCode, 'errorCode', 29)),
      );
    });
  });
}