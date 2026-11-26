import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/musicbrainz/musicbrainz_api_exception.dart';
import 'package:playtier/data/services/musicbrainz/musicbrainz_service.dart';

/// Records every request (with the time it arrived) and answers with
/// [body] and [status].
({
  MusicBrainzService api,
  List<http.Request> requests,
  List<DateTime> times,
}) fakeApi(
  Object body, {
  int status = 200,
  Duration minInterval = Duration.zero,
}) {
  final requests = <http.Request>[];
  final times = <DateTime>[];
  final client = MockClient((request) async {
    requests.add(request);
    times.add(DateTime.now());
    return http.Response(body is String ? body : jsonEncode(body), status);
  });
  return (
    api: MusicBrainzService(client, minInterval: minInterval),
    requests: requests,
    times: times,
  );
}

const _mbid = 'a74b1b7f-71a5-4011-9441-d0b5e4122711';

void main() {
  group('findArtistBySpotifyId', () {
    test('looks up the Spotify URL and returns the linked artist', () async {
      final fake = fakeApi({
        'resource': 'https://open.spotify.com/artist/sp1',
        'relations': [
          {
            'type': 'free streaming',
            'artist': {'id': _mbid, 'name': 'Radiohead'},
          },
        ],
      });

      expect(await fake.api.findArtistBySpotifyId('sp1'), _mbid);

      final request = fake.requests.single;
      expect(request.url.host, 'musicbrainz.org');
      expect(request.url.path, '/ws/2/url');
      expect(request.url.queryParameters, {
        'resource': 'https://open.spotify.com/artist/sp1',
        'inc': 'artist-rels',
        'fmt': 'json',
      });
      expect(request.headers['User-Agent'], MusicBrainzService.userAgent);
    });

    test('unknown URL (404) returns null', () async {
      final fake = fakeApi({'error': 'Not Found'}, status: 404);
      expect(await fake.api.findArtistBySpotifyId('sp1'), isNull);
    });

    test('relations without an artist return null', () async {
      final fake = fakeApi({
        'relations': [
          {'type': 'free streaming', 'release': {'id': 'r1'}},
        ],
      });
      expect(await fake.api.findArtistBySpotifyId('sp1'), isNull);
    });
  });

  group('searchArtist', () {
    test('quotes and escapes the name', () async {
      final fake = fakeApi({'artists': []});
      await fake.api.searchArtist(r'The "Big" \ Band');

      final params = fake.requests.single.url.queryParameters;
      expect(fake.requests.single.url.path, '/ws/2/artist');
      expect(params['query'], r'artist:"The \"Big\" \\ Band"');
      expect(params['limit'], '1');
      expect(params['fmt'], 'json');
    });

    test('returns the best match when its score is high enough', () async {
      final fake = fakeApi({
        'artists': [
          {'id': _mbid, 'name': 'Radiohead', 'score': 100},
        ],
      });
      expect(await fake.api.searchArtist('Radiohead'), _mbid);
    });

    test('a low score returns null', () async {
      final fake = fakeApi({
        'artists': [
          {'id': _mbid, 'name': 'Radio Head Band', 'score': 70},
        ],
      });
      expect(await fake.api.searchArtist('Radiohead'), isNull);
      expect(await fake.api.searchArtist('Radiohead', minScore: 70), _mbid);
    });

    test('no results returns null', () async {
      final fake = fakeApi({'artists': []});
      expect(await fake.api.searchArtist('zzzz'), isNull);
    });
  });

  group('getArtistGenres', () {
    test('requests genres and parses name and votes', () async {
      final fake = fakeApi({
        'id': _mbid,
        'name': 'Radiohead',
        'genres': [
          {'id': 'g1', 'name': 'alternative rock', 'count': 12},
          {'id': 'g2', 'name': 'art rock', 'count': 8},
        ],
      });

      expect(await fake.api.getArtistGenres(_mbid), [
        (name: 'alternative rock', count: 12),
        (name: 'art rock', count: 8),
      ]);
      final request = fake.requests.single;
      expect(request.url.path, '/ws/2/artist/$_mbid');
      expect(request.url.queryParameters, {'inc': 'genres', 'fmt': 'json'});
    });

    test('an artist without genres returns an empty list', () async {
      final fake = fakeApi({'id': _mbid, 'genres': []});
      expect(await fake.api.getArtistGenres(_mbid), isEmpty);
    });

    test('unknown id (404) returns an empty list', () async {
      final fake = fakeApi({'error': 'Not Found'}, status: 404);
      expect(await fake.api.getArtistGenres(_mbid), isEmpty);
    });

    test('rate limited (503) throws', () async {
      final fake = fakeApi('Service Unavailable', status: 503);
      expect(
        fake.api.getArtistGenres(_mbid),
        throwsA(isA<MusicBrainzApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
    });
  });

  group('throttling', () {
    test('parallel calls are sent one after another, spaced', () async {
      const interval = Duration(milliseconds: 100);
      final fake = fakeApi({'genres': []}, minInterval: interval);

      await Future.wait([
        fake.api.getArtistGenres('a'),
        fake.api.getArtistGenres('b'),
        fake.api.getArtistGenres('c'),
      ]);

      expect(
        [for (final r in fake.requests) r.url.pathSegments.last],
        ['a', 'b', 'c'],
      );
      for (var i = 1; i < fake.times.length; i++) {
        final gap = fake.times[i].difference(fake.times[i - 1]);
        expect(gap.inMilliseconds, greaterThanOrEqualTo(90));
      }
    });

    test('a failed request does not block the next one', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('offline');
        return http.Response('{"genres": []}', 200);
      });
      final api = MusicBrainzService(client, minInterval: Duration.zero);

      await expectLater(
        api.getArtistGenres('a'),
        throwsA(isA<http.ClientException>()),
      );
      expect(await api.getArtistGenres('b'), isEmpty);
    });
  });
}