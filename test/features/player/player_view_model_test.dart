import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/domain/models/playback_exception.dart';
import 'package:playtier/domain/models/playback_state.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/features/player/player_view_model.dart';

class MockPlayback extends Mock implements PlaybackRepository {}

final start = DateTime(2026, 1, 1, 12);

PlaybackState playing({bool isPlaying = true}) => PlaybackState(
      trackUri: 'spotify:track:t1',
      trackName: 'Song',
      artistNames: const ['Muse'],
      albumName: 'Album',
      duration: const Duration(minutes: 4),
      position: const Duration(minutes: 1),
      isPlaying: isPlaying,
      updatedAt: start,
    );

/// Lets the stream deliver its events.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late MockPlayback playback;
  late StreamController<PlaybackState?> player;
  late ValueNotifier<bool> loggedIn;
  late DateTime now;
  late PlayerViewModel vm;

  setUp(() {
    playback = MockPlayback();
    player = StreamController<PlaybackState?>.broadcast();
    loggedIn = ValueNotifier(true);
    now = start;
    when(() => playback.state).thenAnswer((_) => player.stream);
    when(playback.pause).thenAnswer((_) async => const Result.ok(null));
    when(playback.resume).thenAnswer((_) async => const Result.ok(null));
    when(playback.next).thenAnswer((_) async => const Result.ok(null));

    vm = PlayerViewModel(
      playback: playback,
      loggedIn: loggedIn,
      clock: () => now,
    );
  });

  tearDown(() async {
    vm.dispose();
    loggedIn.dispose();
    await player.close();
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
}
