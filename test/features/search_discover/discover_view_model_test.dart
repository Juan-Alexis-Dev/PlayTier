import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/discover_repository.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/domain/engines/virtual_playlists.dart';
import 'package:playtier/domain/models/discover_mode.dart';
import 'package:playtier/domain/models/discover_parameter.dart';
import 'package:playtier/domain/models/playlist_draft.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/search_discover/discover_view_model.dart';

class MockDiscover extends Mock implements DiscoverRepository {}

class MockLibrary extends Mock implements LibraryRepository {}

VirtualPlaylist vp(String id, String name) =>
    (id: id, name: name, trackCount: 1, coverUrls: const []);

const track = Track(
  id: 't1',
  uri: 'spotify:track:t1',
  name: 'Uprising',
  artistIds: ['a1'],
  albumId: 'al',
  albumName: 'Album',
  duration: Duration(minutes: 5),
);

const draft = PlaylistDraft(
  name: 'New music from your artists',
  tracks: [track],
);

void main() {
  late MockDiscover discover;
  late MockLibrary library;
  late DiscoverViewModel vm;

  setUp(() async {
    discover = MockDiscover();
    library = MockLibrary();
    when(() => discover.isAvailable).thenReturn(true);
    // Library order: most tracks first.
    when(library.watchArtistPlaylists).thenAnswer((_) => Stream.value([
          vp('a1', 'Muse'),
          vp('a2', 'Radiohead'),
          vp('a3', 'Mumford & Sons'),
        ]));
    when(library.watchGenrePlaylists).thenAnswer((_) => Stream.value([
          vp('rock', 'Rock'),
          vp('alternative rock', 'Alternative Rock'),
        ]));
    vm = DiscoverViewModel(discover: discover, library: library)..init();
    await Future<void>.delayed(Duration.zero); // let the streams emit
  });
  tearDown(() => vm.dispose());

  void stubRun(Future<Result<PlaylistDraft>> Function() answer) {
    when(() => discover.newFromYourArtists(maxTracks: any(named: 'maxTracks')))
        .thenAnswer((_) => answer());
  }

  test('only ready modes can run', () {
    expect(vm.canRun(DiscoverMode.fromArtists), isTrue);
    expect(vm.canRun(DiscoverMode.fromGenres), isTrue);
    expect(vm.canRun(DiscoverMode.youCouldLike), isTrue);
    expect(vm.canRun(DiscoverMode.toTry), isTrue);
    // Own parameters needs at least one chip.
    expect(vm.isReady(DiscoverMode.custom), isTrue);
    expect(vm.canRun(DiscoverMode.custom), isFalse);
  });

  test('nothing can run without Last.fm', () {
    when(() => discover.isAvailable).thenReturn(false);

    expect(vm.isAvailable, isFalse);
    expect(vm.canRun(DiscoverMode.fromArtists), isFalse);
  });

  test('a successful run returns the draft and clears running', () async {
    final completer = Completer<Result<PlaylistDraft>>();
    stubRun(() => completer.future);

    final future = vm.run(DiscoverMode.fromArtists);
    expect(vm.running, DiscoverMode.fromArtists);
    expect(vm.busy, isTrue);

    completer.complete(const Result.ok(draft));
    expect(await future, draft);
    expect(vm.running, isNull);
    expect(vm.errorMessage, isNull);
  });

  test('an empty result returns null with a message', () async {
    stubRun(() async => const Result.ok(
          PlaylistDraft(name: 'x', tracks: []),
        ));

    expect(await vm.run(DiscoverMode.fromArtists), isNull);
    expect(vm.errorMessage, DiscoverViewModel.emptyText);
  });

  test('an error returns null with a message', () async {
    stubRun(() async => Result.error(Exception('offline')));

    expect(await vm.run(DiscoverMode.fromArtists), isNull);
    expect(vm.errorMessage, DiscoverViewModel.errorText);
    expect(vm.busy, isFalse);
  });

  test('a new run clears the previous error', () async {
    stubRun(() async => Result.error(Exception('offline')));
    await vm.run(DiscoverMode.fromArtists);

    stubRun(() async => const Result.ok(draft));
    await vm.run(DiscoverMode.fromArtists);

    expect(vm.errorMessage, isNull);
  });

  test('a second tap while running is ignored', () async {
    final completer = Completer<Result<PlaylistDraft>>();
    stubRun(() => completer.future);

    final first = vm.run(DiscoverMode.fromArtists);
    expect(await vm.run(DiscoverMode.fromArtists), isNull);
    completer.complete(const Result.ok(draft));
    await first;

    verify(() => discover.newFromYourArtists(
          maxTracks: any(named: 'maxTracks'),
        )).called(1);
  });

  test('own parameters without chips does nothing', () async {
    expect(await vm.run(DiscoverMode.custom), isNull);
    verifyNever(() => discover.newFromYourArtists(
          maxTracks: any(named: 'maxTracks'),
        ));
  });

  test('fromGenres runs newFromYourGenres', () async {
    const genresDraft = PlaylistDraft(
      name: 'New music from your genres',
      tracks: [track],
    );
    when(() => discover.newFromYourGenres(
          maxTracks: any(named: 'maxTracks'),
        )).thenAnswer((_) async => const Result.ok(genresDraft));

    expect(await vm.run(DiscoverMode.fromGenres), genresDraft);
    verifyNever(() => discover.newFromYourArtists(
          maxTracks: any(named: 'maxTracks'),
        ));
  });

  test('youCouldLike runs musicYouCouldLike', () async {
    const likeDraft = PlaylistDraft(
      name: 'Music you could like',
      tracks: [track],
    );
    when(() => discover.musicYouCouldLike(
          maxTracks: any(named: 'maxTracks'),
        )).thenAnswer((_) async => const Result.ok(likeDraft));

    expect(await vm.run(DiscoverMode.youCouldLike), likeDraft);
  });

  test('toTry runs musicToTry', () async {
    const tryDraft = PlaylistDraft(name: 'Music to try', tracks: [track]);
    when(() => discover.musicToTry(maxTracks: any(named: 'maxTracks')))
        .thenAnswer((_) async => const Result.ok(tryDraft));

    expect(await vm.run(DiscoverMode.toTry), tryDraft);
  });

  group('own parameters', () {
    const muse = DiscoverParameter.artist(id: 'a1', label: 'Muse');
    const rock = DiscoverParameter.genre('rock');

    test('suggests artists and genres, names that start first', () {
      expect(vm.suggestions(''), isEmpty);
      expect(vm.suggestions('mu').map((p) => p.label), [
        'Muse',
        'Mumford & Sons',
      ]);
      // "rock" starts with "ro"; "alternative rock" only contains it.
      expect(vm.suggestions(' RO ').map((p) => p.id), [
        'rock',
        'alternative rock',
      ]);
      expect(vm.suggestions('ro').first.isArtist, isFalse);
    });

    test('chosen values are not suggested again', () {
      vm.addParameter(muse);
      expect(vm.suggestions('mu').map((p) => p.label), ['Mumford & Sons']);
    });

    test('adds without repeats, up to the maximum, and removes', () {
      vm.addParameter(muse);
      vm.addParameter(muse);
      expect(vm.selected, [muse]);

      for (var i = 0; i < 10; i++) {
        vm.addParameter(DiscoverParameter.genre('g$i'));
      }
      expect(vm.selected, hasLength(DiscoverViewModel.maxParameters));
      expect(vm.canAddParameter, isFalse);

      vm.removeParameter(muse);
      expect(vm.selected, isNot(contains(muse)));
      expect(vm.canAddParameter, isTrue);
    });

    test('runs with artist names and genres and renames the draft',
        () async {
      when(() => discover.fromOwnParameters(
            artists: any(named: 'artists'),
            genres: any(named: 'genres'),
            maxTracks: any(named: 'maxTracks'),
          )).thenAnswer((_) async => const Result.ok(
            PlaylistDraft(name: 'Own parameters', tracks: [track]),
          ));
      vm.addParameter(muse);
      vm.addParameter(rock);
      expect(vm.canRun(DiscoverMode.custom), isTrue);

      final result = await vm.run(DiscoverMode.custom);

      expect(result?.name, 'Rock · Muse');
      expect(result?.tracks, [track]);
      verify(() => discover.fromOwnParameters(
            artists: ['Muse'],
            genres: ['rock'],
            maxTracks: any(named: 'maxTracks'),
          )).called(1);
    });
  });
}