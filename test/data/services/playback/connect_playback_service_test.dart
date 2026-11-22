import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/playback/connect_playback_service.dart';
import 'package:playtier/data/services/spotify/dto/spotify_player_dto.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/playback_exception.dart';
import 'package:playtier/domain/models/playback_state.dart';

Map<String, dynamic> device(
  String id, {
  String type = 'Computer',
  bool active = false,
  bool restricted = false,
}) =>
    {
      'id': id,
      'name': 'Device $id',
      'type': type,
      'is_active': active,
      'is_restricted': restricted,
    };

/// Fake Web API: answers `/devices` with [devices], records every request.
class FakeSpotify {
  FakeSpotify(this.devices, {this.playStatus = 204});

  final List<Map<String, dynamic>> devices;
  final int playStatus;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/me/player/devices')) {
      return http.Response(jsonEncode({'devices': devices}), 200);
    }
    if (path.endsWith('/me/player')) return http.Response('', 204);
    if (path.endsWith('/me/player/play')) {
      return http.Response(playStatus == 204 ? '' : '{"error":{}}', playStatus);
    }
    return http.Response('', 204);
  });

  ConnectPlaybackService service() => ConnectPlaybackService(
        SpotifyApiService(client),
        delay: (_) async {},
      );

  http.Request get play =>
      requests.firstWhere((r) => r.url.path.endsWith('/me/player/play'));
}

void main() {
  group('playContext', () {
    test('plays on the active device with offset, then turns shuffle off',
        () async {
      final fake = FakeSpotify([
        device('pc'),
        device('phone', type: 'Smartphone', active: true),
      ]);
      await fake.service().playContext('spotify:playlist:p1', startIndex: 3);

      expect(fake.play.method, 'PUT');
      expect(fake.play.url.queryParameters['device_id'], 'phone');
      expect(jsonDecode(fake.play.body), {
        'context_uri': 'spotify:playlist:p1',
        'offset': {'position': 3},
      });

      final shuffle = fake.requests
          .firstWhere((r) => r.url.path.endsWith('/me/player/shuffle'));
      expect(shuffle.url.queryParameters['state'], 'false');
      expect(shuffle.url.queryParameters['device_id'], 'phone');
    });

    test('without an active device, prefers a computer', () async {
      final fake = FakeSpotify([
        device('speaker', type: 'Speaker'),
        device('pc'),
      ]);
      await fake.service().playContext('spotify:playlist:p1');
      expect(fake.play.url.queryParameters['device_id'], 'pc');
    });

    test('skips restricted devices', () async {
      final fake = FakeSpotify([
        device('locked', active: true, restricted: true),
        device('speaker', type: 'Speaker'),
      ]);
      await fake.service().playContext('spotify:playlist:p1');
      expect(fake.play.url.queryParameters['device_id'], 'speaker');
    });

    test('throws noDevice when Spotify is not open anywhere', () async {
      final fake = FakeSpotify([]);
      await expectLater(
        fake.service().playContext('spotify:playlist:p1'),
        throwsA(
          isA<PlaybackException>()
              .having((e) => e.kind, 'kind', PlaybackErrorKind.noDevice),
        ),
      );
    });

    test('maps a Web API error to rejected', () async {
      final fake = FakeSpotify([device('pc')], playStatus: 403);
      await expectLater(
        fake.service().playContext('spotify:playlist:p1'),
        throwsA(
          isA<PlaybackException>()
              .having((e) => e.kind, 'kind', PlaybackErrorKind.rejected),
        ),
      );
    });
  });

  test('simple commands call the right endpoints', () async {
    final fake = FakeSpotify([]);
    final service = fake.service();
    await service.pause();
    await service.next();
    await service.seek(const Duration(seconds: 42));
    await service.setRepeat(RepeatMode.context);

    final calls = [
      for (final r in fake.requests) '${r.method} ${r.url.path.split('/').last}',
    ];
    expect(calls, ['PUT pause', 'POST next', 'PUT seek', 'PUT repeat']);
    expect(fake.requests[2].url.queryParameters['position_ms'], '42000');
    expect(fake.requests[3].url.queryParameters['state'], 'context');
  });

  group('toState', () {
    final now = DateTime(2026, 1, 1);

    test('null player or no track gives null', () {
      expect(ConnectPlaybackService.toState(null, now), isNull);
      final noTrack = SpotifyPlayerDto.fromJson(
        {'is_playing': true, 'item': null},
      );
      expect(ConnectPlaybackService.toState(noTrack, now), isNull);
    });

    test('maps the Web API player', () {
      final player = SpotifyPlayerDto.fromJson({
        'is_playing': true,
        'progress_ms': 61000,
        'shuffle_state': false,
        'repeat_state': 'track',
        'device': device('pc', active: true),
        'context': {'uri': 'spotify:playlist:p1'},
        'item': {
          'type': 'track',
          'uri': 'spotify:track:t1',
          'name': 'Song',
          'duration_ms': 200000,
          'artists': [
            {'name': 'A'},
            {'name': 'B'},
          ],
          'album': {
            'name': 'Album',
            'images': [
              {'url': 'https://img/1'},
            ],
          },
        },
      });
      final state = ConnectPlaybackService.toState(player, now)!;
      expect(state.trackId, 't1');
      expect(state.artistNames, ['A', 'B']);
      expect(state.position, const Duration(seconds: 61));
      expect(state.repeatMode, RepeatMode.track);
      expect(state.contextUri, 'spotify:playlist:p1');
      expect(state.deviceName, 'Device pc');
      expect(state.coverUrl, 'https://img/1');
      expect(state.updatedAt, now);
    });
  });
}