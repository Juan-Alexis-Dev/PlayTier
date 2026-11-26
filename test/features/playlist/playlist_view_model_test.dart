import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/levels_repository.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/data/repositories/playlist_repository.dart';
import 'package:playtier/data/repositories/settings_repository.dart';
import 'package:playtier/domain/models/filter_criteria.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/playlist/playlist_view_model.dart';

class MockLibrary extends Mock implements LibraryRepository {}

class MockLevels extends Mock implements LevelsRepository {}

class MockPlayback extends Mock implements PlaybackRepository {}

class MockPlaylists extends Mock implements PlaylistRepository {}

class MockSettings extends Mock implements SettingsRepository {}

Track track(String id, String artist) => Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: [artist],
      albumId: 'al1',
      albumName: 'Album',
      duration: const Duration(minutes: 3),
    );

void main() {
  late MockLibrary library;
  late MockLevels levels;
  late MockPlayback playback;
  late MockPlaylists playlists;
  late MockSettings settings;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<Track>[]);
  });

  setUp(() {
    library = MockLibrary();
    levels = MockLevels();
    playback = MockPlayback();
    playlists = MockPlaylists();
    settings = MockSettings();
    when(library.watchArtistGenres).thenAnswer((_) => Stream.value(const {}));
    when(levels.watchLevels).thenAnswer((_) => Stream.value(const {}));
    when(
      () => playback.playList(
        any(),
        startIndex: any(named: 'startIndex'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async => const Result.ok(null));
  });

  PlaylistViewModel permanent() => PlaylistViewModel(
        playlistId: 'perm1',
        library: library,
        levels: levels,
        playback: playback,
        playlists: playlists,
        settings: settings,
      );

  group('permanent playlist', () {
    setUp(() {
      when(() => playlists.getPlaylistContent('perm1')).thenAnswer(
        (_) async => Result.ok((
          name: 'Road trip',
          coverUrl: 'https://img/1',
          tracks: [track('1', 'a'), track('2', 'b')],
          artistNames: const {'a': 'Muse', 'b': 'Blur'},
        )),
      );
    });

    test('loads name, cover and tracks from Spotify, not the cache',
        () async {
      final vm = permanent();
      await vm.init();

      expect(vm.isMain, isFalse);
      expect(vm.loaded, isTrue);
      expect(vm.name, 'Road trip');
      expect(vm.coverUrl, 'https://img/1');
      expect(vm.tracks.map((t) => t.id), ['1', '2']);
      expect(vm.artistsOf(vm.tracks.first), 'Muse');
      verifyNever(library.watchTracks);
      verifyNever(library.syncIfChanged);
    });

    test('Play without filters plays the playlist itself', () async {
      final vm = permanent();
      await vm.init();
      await vm.play();

      verify(
        () => playback.playList('spotify:playlist:perm1', name: 'Road trip'),
      ).called(1);
      verifyNever(() => playlists.writePlaybackPlaylist(any()));
      verifyNever(settings.getMainPlaylistId);
    });

    test('Play with filters plays the visible list (temporary)', () async {
      when(() => playlists.writePlaybackPlaylist(any()))
          .thenAnswer((_) async => const Result.ok('spotify:playlist:pb'));

      final vm = permanent();
      await vm.init();
      vm.setFilters(FilterCriteria(artistIds: {'b'}));
      await vm.play();

      verify(() => playlists.writePlaybackPlaylist(['spotify:track:2']))
          .called(1);
      verify(
        () => playback.playList('spotify:playlist:pb', name: 'Road trip'),
      ).called(1);
    });

    test('Shuffle plays the visible list with weights', () async {
      when(() => playback.playShuffled(any(), name: any(named: 'name')))
          .thenAnswer((_) async => const Result.ok(null));

      final vm = permanent();
      await vm.init();
      vm.setFilters(FilterCriteria(artistIds: {'b'}));
      await vm.shuffle();

      final shuffled = verify(
        () => playback.playShuffled(captureAny(), name: 'Road trip'),
      )
          .captured
          .single as List<Track>;
      expect(shuffled.map((t) => t.id), ['2']);
      expect(vm.starting, isFalse);
      expect(vm.errorMessage, isNull);
    });

    test('a Shuffle error shows a message', () async {
      when(() => playback.playShuffled(any(), name: any(named: 'name')))
          .thenAnswer((_) async => Result.error(Exception('offline')));

      final vm = permanent();
      await vm.init();
      await vm.shuffle();

      expect(vm.errorMessage, 'Could not start playback.');
      expect(vm.starting, isFalse);
    });

    test('refresh reads the playlist again', () async {
      final vm = permanent();
      await vm.init();
      await vm.sync();
      verify(() => playlists.getPlaylistContent('perm1')).called(2);
    });
  });

  group('Liked page', () {
    final tracks = [
      track('l1', 'a'),
      track('l2', 'a'),
      track('l3', 'a'),
      track('l4', 'a'),
    ];

    setUp(() {
      when(library.watchTracks).thenAnswer((_) => Stream.value(tracks));
      when(library.watchArtistNames)
          .thenAnswer((_) => Stream.value(const {'a': 'Muse'}));
      when(() => library.syncIfChanged())
          .thenAnswer((_) async => const Result.ok(false));
      // l1 has no row (level 1), l2 is level 1, l3 is 2, l4 is 5.
      when(levels.watchLevels).thenAnswer(
        (_) => Stream.value(const {'l2': 1, 'l3': 2, 'l4': 5}),
      );
      when(() => playlists.writePlaybackPlaylist(any()))
          .thenAnswer((_) async => const Result.ok('spotify:playlist:pb'));
    });

    Future<PlaylistViewModel> liked() async {
      final vm = PlaylistViewModel(
        isLiked: true,
        library: library,
        levels: levels,
        playback: playback,
        playlists: playlists,
        settings: settings,
      );
      await vm.init();
      return vm;
    }

    test('shows only main tracks with level 2–5', () async {
      final vm = await liked();

      expect(vm.isLiked, isTrue);
      expect(vm.isMain, isFalse);
      expect(vm.name, 'Liked');
      expect(vm.tracks.map((t) => t.id), ['l3', 'l4']);
      expect(vm.totalCount, 2);
      verifyNever(library.getMainPlaylistInfo);
    });

    test('the level filter only shows or hides tracks', () async {
      final vm = await liked();

      vm.toggleLevel(5);
      expect(vm.tracks.map((t) => t.id), ['l3']);
      expect(vm.shownLevels, {2, 3, 4});
      expect(vm.totalCount, 2);
      expect(vm.isCustomized, isFalse);

      vm.toggleLevel(5);
      expect(vm.tracks.map((t) => t.id), ['l3', 'l4']);
    });

    test('levels outside 2–5 cannot be toggled', () async {
      final vm = await liked();

      vm.toggleLevel(1);
      expect(vm.shownLevels, PlaylistViewModel.likedLevels);
    });

    test('Play writes the visible list (there is no Liked playlist)',
        () async {
      final vm = await liked();
      await vm.play();

      verify(
        () => playlists.writePlaybackPlaylist(
          ['spotify:track:l3', 'spotify:track:l4'],
        ),
      ).called(1);
      verify(() => playback.playList('spotify:playlist:pb', name: 'Liked'))
          .called(1);
      verifyNever(settings.getMainPlaylistId);
    });

    test('Shuffle uses the shown tracks (weights come from levels)',
        () async {
      when(() => playback.playShuffled(any(), name: any(named: 'name')))
          .thenAnswer((_) async => const Result.ok(null));
      final vm = await liked();
      vm.toggleLevel(2);

      await vm.shuffle();

      final shuffled = verify(
        () => playback.playShuffled(captureAny(), name: 'Liked'),
      ).captured.single as List<Track>;
      expect(shuffled.map((t) => t.id), ['l4']);
    });

    test('a draft without filters is named Liked', () async {
      final vm = await liked();
      expect(vm.createDraft().name, 'Liked');
    });
  });

  test('a load error shows a message and an empty list', () async {
    when(() => playlists.getPlaylistContent('perm1'))
        .thenAnswer((_) async => Result.error(Exception('offline')));

    final vm = permanent();
    await vm.init();

    expect(vm.loaded, isTrue);
    expect(vm.tracks, isEmpty);
    expect(vm.errorMessage, isNotNull);
  });
}