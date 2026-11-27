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
  late MockPlaylists playlists;

  setUp(() {
    library = MockLibrary();
    levels = MockLevels();
    playlists = MockPlaylists();
    when(library.watchArtistGenres).thenAnswer((_) => Stream.value(const {}));
    when(levels.watchLevels).thenAnswer((_) => Stream.value(const {}));
    when(() => playlists.getPlaylistContent('perm1')).thenAnswer(
      (_) async => Result.ok((
        name: 'Road trip',
        coverUrl: null,
        tracks: [track('1', 'a'), track('2', 'b')],
        artistNames: const {'a': 'Muse', 'b': 'Blur'},
      )),
    );
  });

  PlaylistViewModel vmFor({String? playlistId, String? genre}) =>
      PlaylistViewModel(
        playlistId: playlistId,
        genre: genre,
        library: library,
        levels: levels,
        playback: MockPlayback(),
        playlists: playlists,
        settings: MockSettings(),
      );

  test('a permanent playlist can add music', () {
    final vm = vmFor(playlistId: 'perm1');
    expect(vm.canAddMusic, isTrue);
    vm.dispose();
  });

  test('a genre playlist cannot add music (FR-9.5)', () {
    final vm = vmFor(genre: 'rock');
    expect(vm.canAddMusic, isFalse);
    vm.dispose();
  });

  test('trackIds has every track, even with filters', () async {
    final vm = vmFor(playlistId: 'perm1');
    await vm.init();

    vm.setFilters(FilterCriteria(artistIds: {'a'}));

    expect(vm.tracks.map((t) => t.id), ['1']);
    expect(vm.trackIds, {'1', '2'});
    vm.dispose();
  });
}