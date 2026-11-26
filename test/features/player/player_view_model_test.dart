import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/levels_repository.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/domain/models/like_level.dart';
import 'package:playtier/domain/models/playback_exception.dart';
import 'package:playtier/domain/models/playback_state.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/features/player/player_view_model.dart';

class MockPlayback extends Mock implements PlaybackRepository {}

class MockLevels extends Mock implements LevelsRepository {}

final start = DateTime(2026, 1, 1, 12);

PlaybackState playing({
  bool isPlaying = true,
  RepeatMode repeatMode = RepeatMode.off,
}) =>
    PlaybackState(
      trackUri: 'spotify:track:t1',
      trackName: 'Song',
      artistNames: const ['Muse'],
      albumName: 'Album',
      duration: const Duration(minutes: 4),
      position: const Duration(minutes: 1),
      isPlaying: isPlaying,
      updatedAt: start,
      repeatMode: repeatMode,
    );

/// Lets the stream deliver its events.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late MockPlayback playback;
  late MockLevels levels;
  late StreamController<PlaybackState?> player;
  late StreamController<Map<String, int>> levelRows;
  late ValueNotifier<bool> loggedIn;
  late DateTime now;
  late PlayerViewModel vm;

  setUpAll(() {
    registerFallbackValue(LikeLevel.defaultLevel);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(RepeatMode.off);
    registerFallbackValue(playing());
  });

  setUp(() {
    playback = MockPlayback();
    levels = MockLevels();
    player = StreamController<PlaybackState?>.broadcast();
    levelRows = StreamController<Map<String, int>>.broadcast();
    loggedIn = ValueNotifier(true);
    now = start;
    when(() => playback.state).thenAnswer((_) => player.stream);
    when(playback.pause).thenAnswer((_) async => const Result.ok(null));
    when(playback.resume).thenAnswer((_) async => const Result.ok(null));
    when(playback.next).thenAnswer((_) async => const Result.ok(null));
    when(() => playback.seek(any()))
        .thenAnswer((_) async => const Result.ok(null));
    when(() => playback.setRepeat(any()))
        .thenAnswer((_) async => const Result.ok(null));
    when(() => playback.contextNameOf(any())).thenReturn('Road trip');
    when(() => levels.watchLevels()).thenAnswer((_) => levelRows.stream);
    when(() => levels.setLevel(any(), any()))
        .thenAnswer((_) async => const Result.ok(null));

    vm = PlayerViewModel(
      playback: playback,
      levels: levels,
      loggedIn: loggedIn,
      clock: () => now,
    );
  });

  tearDown(() async {
    vm.dispose();
    loggedIn.dispose();
    await player.close();
    await levelRows.close();
  });

  test('shows the player state while logged in', () async {
    vm.init();
    player.add(playing());
    await settle();

    expect(vm.state?.trackName, 'Song');
    expect(vm.isPlaying, isTrue);
  });

  test('does not listen to the player before login', () async {
    loggedIn.value = false;
    vm.init();
    verifyNever(() => playback.state);

    loggedIn.value = true;
    player.add(playing());
    await settle();

    expect(vm.state, isNotNull);
  });

  test('logout clears the state', () async {
    vm.init();
    player.add(playing());
    await settle();

    loggedIn.value = false;
    await settle();

    expect(vm.state, isNull);
    expect(player.hasListener, isFalse);
  });

  test('position and progress are estimated with the clock', () async {
    vm.init();
    player.add(playing());
    await settle();

    now = start.add(const Duration(minutes: 1));

    expect(vm.position, const Duration(minutes: 2));
    expect(vm.progress, 0.5);
  });

  test('progress is 0 without a track', () {
    vm.init();
    expect(vm.progress, 0);
  });

  test('togglePlayPause pauses and shows it before the next poll', () async {
    vm.init();
    player.add(playing());
    await settle();
    now = start.add(const Duration(seconds: 30));

    final message = await vm.togglePlayPause();

    expect(message, isNull);
    verify(playback.pause).called(1);
    expect(vm.isPlaying, isFalse);
    expect(vm.position, const Duration(minutes: 1, seconds: 30));
  });

  test('togglePlayPause resumes when paused', () async {
    vm.init();
    player.add(playing(isPlaying: false));
    await settle();

    await vm.togglePlayPause();

    verify(playback.resume).called(1);
    expect(vm.isPlaying, isTrue);
  });

  test('a failed command returns a message and keeps the state', () async {
    when(playback.pause).thenAnswer(
      (_) async =>
          const Result.error(PlaybackException(PlaybackErrorKind.noDevice)),
    );
    vm.init();
    player.add(playing());
    await settle();

    final message = await vm.togglePlayPause();

    expect(message, contains('No active Spotify device'));
    expect(vm.isPlaying, isTrue);
  });

  test('next is forwarded to the repository', () async {
    vm.init();
    expect(await vm.next(), isNull);
    verify(playback.next).called(1);
  });

  group('Now Playing', () {
    Future<void> startPlaying({Map<String, int> rows = const {'t1': 2}}) async {
      vm.init();
      player.add(playing());
      levelRows.add(rows);
      await settle();
    }

    test('contextName comes from the repository', () async {
      await startPlaying();
      expect(vm.contextName, 'Road trip');
    });

    test('currentLevel is the level of the playing track', () async {
      await startPlaying();
      expect(vm.currentLevel, 2);
    });

    test('currentLevel is null for a track not in the main playlist',
        () async {
      await startPlaying(rows: const {'other': 3});
      expect(vm.currentLevel, isNull);
    });

    test('setLevel saves the level of the playing track', () async {
      await startPlaying();

      expect(await vm.setLevel(4), isNull);
      verify(() => levels.setLevel('t1', LikeLevel(4))).called(1);
    });

    test('setLevel does nothing for a track not in the main playlist',
        () async {
      await startPlaying(rows: const {});

      await vm.setLevel(4);
      verifyNever(() => levels.setLevel(any(), any()));
    });

    test('a failed setLevel returns a message', () async {
      when(() => levels.setLevel(any(), any()))
          .thenAnswer((_) async => Result.error(Exception('db')));
      await startPlaying();

      expect(await vm.setLevel(3), 'Could not save the level.');
    });

    test('seek moves the position before the next poll', () async {
      await startPlaying();

      await vm.seek(const Duration(minutes: 3));

      verify(() => playback.seek(const Duration(minutes: 3))).called(1);
      expect(vm.position, const Duration(minutes: 3));
    });

    test('cycleRepeat goes off → playlist → track → off', () async {
      await startPlaying();

      await vm.cycleRepeat();
      expect(vm.state?.repeatMode, RepeatMode.context);
      await vm.cycleRepeat();
      expect(vm.state?.repeatMode, RepeatMode.track);
      await vm.cycleRepeat();
      expect(vm.state?.repeatMode, RepeatMode.off);

      verify(() => playback.setRepeat(RepeatMode.context)).called(1);
      verify(() => playback.setRepeat(RepeatMode.track)).called(1);
      verify(() => playback.setRepeat(RepeatMode.off)).called(1);
    });

    test('logout stops listening to the levels', () async {
      await startPlaying();

      loggedIn.value = false;
      await settle();

      expect(levelRows.hasListener, isFalse);
      expect(vm.currentLevel, isNull);
    });
  });
}