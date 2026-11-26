import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/levels_repository.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/data/repositories/playlist_repository.dart';
import 'package:playtier/data/services/playback/playback_service.dart';
import 'package:playtier/domain/models/playback_device.dart';
import 'package:playtier/domain/models/playback_exception.dart';
import 'package:playtier/domain/models/playback_state.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/track.dart';

class MockPlaybackService extends Mock implements PlaybackService {}

class MockPlaylistRepository extends Mock implements PlaylistRepository {}

class MockLevelsRepository extends Mock implements LevelsRepository {}

const playbackContext = 'spotify:playlist:pb';

Track track(String id) => Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: const ['a1'],
      albumId: 'al1',
      albumName: 'al1',
      duration: const Duration(minutes: 3),
    );

PlaybackState playing(String uri, {String? contextUri = playbackContext}) =>
    PlaybackState(
      trackUri: uri,
      trackName: uri,
      artistNames: const [],
      albumName: '',
      duration: const Duration(minutes: 3),
      position: Duration.zero,
      isPlaying: true,
      updatedAt: DateTime(2026),
      contextUri: contextUri,
    );

/// Lets stream listeners and the async append run.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MockPlaybackService service;
  late MockPlaylistRepository playlists;
  late MockLevelsRepository levels;
  late StreamController<PlaybackState?> player;
  late PlaybackRepository repository;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    service = MockPlaybackService();
    playlists = MockPlaylistRepository();
    levels = MockLevelsRepository();
    player = StreamController<PlaybackState?>.broadcast();

    when(() => service.state).thenAnswer((_) => player.stream);
    when(() => service.playContext(any(), startIndex: any(named: 'startIndex')))
        .thenAnswer((_) async {});
    when(() => playlists.writePlaybackPlaylist(any()))
        .thenAnswer((_) async => const Result.ok(playbackContext));
    when(() => playlists.appendToPlaybackPlaylist(any()))
        .thenAnswer((_) async => const Result.ok(null));
    when(() => levels.watchLevels()).thenAnswer((_) => Stream.value({}));

    repository = PlaybackRepository(
      service,
      playlists: playlists,
      levels: levels,
      random: Random(1),
    );
  });

  tearDown(() async {
    await repository.stopShuffle();
    await player.close();
  });

  /// Uris written by `playShuffled` (the first round).
  List<String> writtenRound() =>
      verify(() => playlists.writePlaybackPlaylist(captureAny()))
          .captured
          .single as List<String>;

  test('playList plays the context from the given index', () async {
    final result =
        await repository.playList('spotify:playlist:p1', startIndex: 2);

    expect(result, isA<Ok<void>>());
    verify(() => service.playContext('spotify:playlist:p1', startIndex: 2))
        .called(1);
  });

  test('errors become Result.error instead of exceptions', () async {
    when(() => service.playContext(any(), startIndex: any(named: 'startIndex')))
        .thenThrow(const PlaybackException(PlaybackErrorKind.noDevice));

    final result = await repository.playList('spotify:playlist:p1');

    expect(result, isA<Error<void>>());
    final error = (result as Error<void>).error as PlaybackException;
    expect(error.kind, PlaybackErrorKind.noDevice);
  });

  test('simple commands also return Result.error', () async {
    when(service.pause)
        .thenThrow(const PlaybackException(PlaybackErrorKind.rejected));
    expect(await repository.pause(), isA<Error<void>>());
  });

  group('playShuffled', () {
    final tracks = [for (final id in ['A', 'B', 'C', 'D', 'E']) track(id)];

    test('writes a weighted round and plays it from the start', () async {
      when(() => levels.watchLevels())
          .thenAnswer((_) => Stream.value({'A': 3}));

      final result = await repository.playShuffled(tracks);

      expect(result, isA<Ok<void>>());
      final round = writtenRound();
      expect(round, hasLength(7));
      expect(round.where((u) => u == 'spotify:track:A'), hasLength(3));
      verify(() => service.playContext(playbackContext, startIndex: 0))
          .called(1);
      expect(repository.isShuffleActive, isTrue);
    });

    test('an empty list does nothing', () async {
      expect(await repository.playShuffled([]), isA<Ok<void>>());
      verifyNever(() => playlists.writePlaybackPlaylist(any()));
      expect(repository.isShuffleActive, isFalse);
    });

    test('a failed write returns the error and does not play', () async {
      when(() => playlists.writePlaybackPlaylist(any()))
          .thenAnswer((_) async => Result.error(Exception('offline')));

      expect(await repository.playShuffled(tracks), isA<Error<void>>());
      verifyNever(
        () => service.playContext(any(), startIndex: any(named: 'startIndex')),
      );
      expect(repository.isShuffleActive, isFalse);
    });

    test('appends a new round a few tracks before the end', () async {
      await repository.playShuffled(tracks);
      final round = writtenRound();

      player.add(playing(round[0]));
      await settle();
      verifyNever(() => playlists.appendToPlaybackPlaylist(any()));

      // 5 tracks, cursor at 2 → 3 left = appendAhead.
      player.add(playing(round[2]));
      await settle();

      final appended =
          verify(() => playlists.appendToPlaybackPlaylist(captureAny()))
              .captured
              .single as List<String>;
      expect(appended, hasLength(5));
      expect(appended.first, isNot(round.last));
    });

    test('keeps appending rounds as playback continues', () async {
      await repository.playShuffled(tracks);
      final round = writtenRound();
      player.add(playing(round[0]));
      await settle();
      player.add(playing(round[2]));
      await settle();
      final second =
          verify(() => playlists.appendToPlaybackPlaylist(captureAny()))
              .captured
              .single as List<String>;

      // Cursor at index 7 of 10 → 3 left.
      player.add(playing(round[3]));
      player.add(playing(round[4]));
      player.add(playing(second[0]));
      player.add(playing(second[1]));
      player.add(playing(second[2]));
      await settle();

      verify(() => playlists.appendToPlaybackPlaylist(any())).called(1);
    });

    test('old states before the round starts are ignored', () async {
      await repository.playShuffled(tracks);
      final round = writtenRound();

      player.add(playing('spotify:track:old', contextUri: 'spotify:album:x'));
      await settle();

      expect(repository.isShuffleActive, isTrue);
      player.add(playing(round[0]));
      await settle();
      expect(repository.isShuffleActive, isTrue);
    });

    test('playing another context ends the session', () async {
      await repository.playShuffled(tracks);
      final round = writtenRound();
      player.add(playing(round[0]));
      await settle();

      player.add(playing(round[1], contextUri: 'spotify:album:x'));
      await settle();

      expect(repository.isShuffleActive, isFalse);
      verifyNever(() => playlists.appendToPlaybackPlaylist(any()));
    });

    test('a track outside the queue ends the session', () async {
      await repository.playShuffled(tracks);
      final round = writtenRound();
      player.add(playing(round[0]));
      await settle();

      player.add(playing('spotify:track:other', contextUri: null));
      await settle();

      expect(repository.isShuffleActive, isFalse);
    });

    test('playList ends the session', () async {
      await repository.playShuffled(tracks);

      await repository.playList('spotify:playlist:p1');

      expect(repository.isShuffleActive, isFalse);
    });

    test('a failed append is retried on the next player state', () async {
      when(() => playlists.appendToPlaybackPlaylist(any()))
          .thenAnswer((_) async => Result.error(Exception('offline')));
      await repository.playShuffled(tracks);
      final round = writtenRound();
      player.add(playing(round[0]));
      await settle();

      player.add(playing(round[2]));
      await settle();
      player.add(playing(round[3]));
      await settle();

      verify(() => playlists.appendToPlaybackPlaylist(any())).called(2);
      expect(repository.isShuffleActive, isTrue);
    });
  });

  group('contextNameOf', () {
    test('is the name given to playList while that context plays', () async {
      await repository.playList('spotify:playlist:p1', name: 'Road trip');

      expect(
        repository.contextNameOf(
          playing('spotify:track:A', contextUri: 'spotify:playlist:p1'),
        ),
        'Road trip',
      );
    });

    test('is null when Spotify plays another context', () async {
      await repository.playList('spotify:playlist:p1', name: 'Road trip');

      expect(
        repository.contextNameOf(
          playing('spotify:track:A', contextUri: 'spotify:album:x'),
        ),
        isNull,
      );
    });

    test('is kept when the context is unknown (Android)', () async {
      await repository.playList('spotify:playlist:p1', name: 'Road trip');

      expect(
        repository.contextNameOf(playing('spotify:track:A', contextUri: null)),
        'Road trip',
      );
    });

    test('playShuffled sets the name for the playback playlist', () async {
      await repository.playShuffled([track('A')], name: 'Main playlist');

      expect(
        repository.contextNameOf(playing('spotify:track:A')),
        'Main playlist',
      );
    });

    test('is not set when playback fails', () async {
      when(
        () => service.playContext(any(), startIndex: any(named: 'startIndex')),
      ).thenThrow(const PlaybackException(PlaybackErrorKind.noDevice));

      await repository.playList('spotify:playlist:p1', name: 'Road trip');

      expect(
        repository.contextNameOf(
          playing('spotify:track:A', contextUri: 'spotify:playlist:p1'),
        ),
        isNull,
      );
    });
  });

  group('devices', () {
    const pc = PlaybackDevice(id: 'pc', name: 'PC', type: 'Computer');

    test('getDevices returns the service devices', () async {
      when(service.getDevices).thenAnswer((_) async => [pc]);

      final result = await repository.getDevices();

      expect((result as Ok<List<PlaybackDevice>>).value, [pc]);
    });

    test('getDevices errors become Result.error', () async {
      when(service.getDevices)
          .thenThrow(const PlaybackException(PlaybackErrorKind.rejected));

      expect(await repository.getDevices(), isA<Error<List<PlaybackDevice>>>());
    });

    test('transferTo moves playback without ending the shuffle', () async {
      when(() => service.transferTo(any())).thenAnswer((_) async {});
      await repository.playShuffled([track('A'), track('B')]);

      expect(await repository.transferTo('pc'), isA<Ok<void>>());
      verify(() => service.transferTo('pc')).called(1);
      expect(repository.isShuffleActive, isTrue);
    });
  });
}