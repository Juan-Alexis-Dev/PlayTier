import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/data/repositories/playlist_repository.dart';
import 'package:playtier/domain/engines/playlist_name_generator.dart';
import 'package:playtier/domain/models/playback_exception.dart';
import 'package:playtier/domain/models/playlist_draft.dart';
import 'package:playtier/domain/models/playlist_summary.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/preview/preview_view_model.dart';

class MockLibrary extends Mock implements LibraryRepository {}

class MockPlayback extends Mock implements PlaybackRepository {}

class MockPlaylists extends Mock implements PlaylistRepository {}

Track track(String id, {String? cover}) => Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: const ['a1'],
      albumId: 'al1',
      albumName: 'Album',
      duration: const Duration(minutes: 3),
      coverUrl: cover,
    );

void main() {
  late MockLibrary library;
  late MockPlayback playback;
  late MockPlaylists playlists;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    library = MockLibrary();
    playback = MockPlayback();
    playlists = MockPlaylists();
    when(library.watchArtistNames)
        .thenAnswer((_) => Stream.value(const {'a1': 'Artist'}));
  });

  PreviewViewModel create({String name = 'Rock', List<Track>? tracks}) =>
      PreviewViewModel(
        draft: PlaylistDraft(
          name: name,
          tracks: tracks ?? [track('1'), track('2'), track('3')],
        ),
        library: library,
        playback: playback,
        playlists: playlists,
      )..init();

  test('remove and undo keep the order', () {
    final vm = create();
    final removed = vm.removeAt(1);
    expect(vm.tracks.map((t) => t.id), ['1', '3']);

    vm.undoRemove(1, removed);
    expect(vm.tracks.map((t) => t.id), ['1', '2', '3']);
  });

  test('cannot finish with no tracks', () {
    final vm = create(tracks: [track('1')])..removeAt(0);
    expect(vm.canFinish, isFalse);
  });

  test('blank name is saved with the fallback name', () {
    final vm = create()..rename('   ');
    expect(vm.nameToSave, PlaylistNameGenerator.fallback);
    vm.rename('  Road trip ');
    expect(vm.nameToSave, 'Road trip');
  });

  group('Temporary', () {
    test('writes the tracks in order, then plays that playlist', () async {
      when(() => playlists.writePlaybackPlaylist(any()))
          .thenAnswer((_) async => const Result.ok('spotify:playlist:pb'));
      when(() => playback.playList(any(), name: any(named: 'name')))
          .thenAnswer((_) async => const Result.ok(null));

      final vm = create()..removeAt(0);
      await vm.playTemporary();

      verify(() => playlists.writePlaybackPlaylist(
            ['spotify:track:2', 'spotify:track:3'],
          )).called(1);
      verify(() => playback.playList('spotify:playlist:pb', name: 'Rock'))
          .called(1);
      expect(vm.outcome, PreviewOutcome.played);
      expect(vm.errorMessage, isNull);
      expect(vm.busy, isFalse);
    });

    test('playback errors become a message', () async {
      when(() => playlists.writePlaybackPlaylist(any()))
          .thenAnswer((_) async => const Result.ok('spotify:playlist:pb'));
      when(() => playback.playList(any(), name: any(named: 'name'))).thenAnswer(
        (_) async => const Result.error(
          PlaybackException(PlaybackErrorKind.noDevice),
        ),
      );

      final vm = create();
      await vm.playTemporary();

      expect(vm.outcome, isNull);
      expect(vm.errorMessage, contains('No active Spotify device'));
    });

    test('does not play if writing fails', () async {
      when(() => playlists.writePlaybackPlaylist(any()))
          .thenAnswer((_) async => Result.error(Exception('offline')));

      final vm = create();
      await vm.playTemporary();

      verifyNever(
        () => playback.playList(any(), name: any(named: 'name')),
      );
      expect(vm.errorMessage, isNotNull);
    });
  });

  group('Permanent', () {
    test('creates the playlist with the name and tracks', () async {
      when(() => playlists.createPermanent(any(), any())).thenAnswer(
        (_) async => const Result.ok(
          PlaylistSummary(
            id: 'new1',
            name: 'Rock',
            trackCount: 3,
            type: PlaylistType.permanent,
          ),
        ),
      );

      final vm = create();
      await vm.savePermanent();

      verify(() => playlists.createPermanent(
            'Rock',
            ['spotify:track:1', 'spotify:track:2', 'spotify:track:3'],
          )).called(1);
      verifyNever(
        () => playback.playList(any(), name: any(named: 'name')),
      );
      expect(vm.outcome, PreviewOutcome.saved);
    });

    test('a Discover draft is saved without touching the main playlist',
        () async {
      when(() => playlists.createPermanent(any(), any())).thenAnswer(
        (_) async => const Result.ok(
          PlaylistSummary(
            id: 'new2',
            name: 'Music to try',
            trackCount: 1,
            type: PlaylistType.permanent,
          ),
        ),
      );
      final vm = PreviewViewModel(
        draft: PlaylistDraft(
          name: 'Music to try',
          tracks: [track('x')],
          artistNames: const {'a1': 'New Artist'},
        ),
        library: library,
        playback: playback,
        playlists: playlists,
      )..init();

      await vm.savePermanent();

      expect(vm.outcome, PreviewOutcome.saved);
      verifyNever(() => library.addToMain(any()));
      verifyNever(() => library.syncIfChanged(force: any(named: 'force')));
    });

    test('errors become a message', () async {
      when(() => playlists.createPermanent(any(), any()))
          .thenAnswer((_) async => Result.error(Exception('403')));

      final vm = create();
      await vm.savePermanent();

      expect(vm.outcome, isNull);
      expect(vm.errorMessage, isNotNull);
    });
  });

  test('draft cover uses up to 4 different covers in order', () {
    final draft = PlaylistDraft(name: 'x', tracks: [
      track('1', cover: 'c1'),
      track('2', cover: 'c1'),
      track('3'),
      track('4', cover: 'c2'),
      track('5', cover: 'c3'),
      track('6', cover: 'c4'),
      track('7', cover: 'c5'),
    ]);
    expect(draft.coverUrls, ['c1', 'c2', 'c3', 'c4']);
  });

  group('artist names', () {
    Track discoverTrack() => const Track(
          id: 'd1',
          uri: 'spotify:track:d1',
          name: 'Hit',
          artistIds: ['a1', 'new'],
          albumId: 'al',
          albumName: 'Album',
          duration: Duration(minutes: 3),
        );

    PreviewViewModel createWith(Map<String, String> draftNames) =>
        PreviewViewModel(
          draft: PlaylistDraft(
            name: 'x',
            tracks: [discoverTrack()],
            artistNames: draftNames,
          ),
          library: library,
          playback: playback,
          playlists: playlists,
        )..init();

    test('unknown artists use the names that came with the draft',
        () async {
      final vm = createWith(const {'new': 'New Artist'});
      await Future<void>.delayed(Duration.zero);

      // 'a1' comes from the library ("Artist"), 'new' from the draft.
      expect(vm.artistsOf(discoverTrack()), 'Artist, New Artist');
    });

    test('the library name wins over the draft name', () async {
      final vm = createWith(const {'a1': 'Old Name', 'new': 'New Artist'});
      await Future<void>.delayed(Duration.zero);

      expect(vm.artistsOf(discoverTrack()), 'Artist, New Artist');
    });

    test('artists with no name anywhere are skipped', () async {
      final vm = createWith(const {});
      await Future<void>.delayed(Duration.zero);

      expect(vm.artistsOf(discoverTrack()), 'Artist');
    });

    test('the edited draft keeps the artist names', () {
      final vm = createWith(const {'new': 'New Artist'})..rename('Mine');

      expect(vm.draft.name, 'Mine');
      expect(vm.draft.artistNames, {'new': 'New Artist'});
    });
  });
}