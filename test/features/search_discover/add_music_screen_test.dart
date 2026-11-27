import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/playlist_repository.dart';
import 'package:playtier/data/repositories/search_repository.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/search_discover/add_music_screen.dart';
import 'package:playtier/features/search_discover/search_view_model.dart';
import 'package:provider/provider.dart';

class MockSearch extends Mock implements SearchRepository {}

class MockLibrary extends Mock implements LibraryRepository {}

class MockPlaylists extends Mock implements PlaylistRepository {}

SearchResult result(String id, {bool inMain = false}) => SearchResult(
      track: Track(
        id: id,
        uri: 'spotify:track:$id',
        name: 'Song $id',
        artistIds: const ['a1'],
        albumId: 'al1',
        albumName: 'Album',
        duration: const Duration(minutes: 3),
      ),
      artistNames: const ['Muse'],
      inMain: inMain,
    );

void main() {
  late MockSearch search;
  late MockLibrary library;
  late MockPlaylists playlists;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    search = MockSearch();
    library = MockLibrary();
    playlists = MockPlaylists();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    const target = AddMusicTarget(
      name: 'Road trip',
      playlistId: 'perm1',
      trackIds: {'t1'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => SearchViewModel(
            search: search,
            library: library,
            playlists: playlists,
            targetPlaylistId: target.playlistId,
            targetName: target.name,
            targetTrackIds: target.trackIds,
            debounce: Duration.zero,
          ),
          child: const AddMusicScreen(target: target),
        ),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the playlist name and the hint', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Add to Road trip'), findsOneWidget);
    expect(find.textContaining('add to this playlist'), findsOneWidget);
  });

  testWidgets('tracks of the playlist show a check, the rest "Add"',
      (tester) async {
    when(() => search.search('muse', offset: 0)).thenAnswer(
      (_) async => Result.ok([result('t1'), result('t2', inMain: true)]),
    );
    await pumpScreen(tester);

    await type(tester, 'muse');

    expect(find.byTooltip('In this playlist'), findsOneWidget);
    expect(find.byTooltip('Add to this playlist'), findsOneWidget);
  });

  testWidgets('"Add" adds to the playlist and to main', (tester) async {
    when(() => search.search('muse', offset: 0))
        .thenAnswer((_) async => Result.ok([result('t2')]));
    when(() => playlists.addTracks(any(), any()))
        .thenAnswer((_) async => const Result.ok(null));
    when(() => library.addToMain(any()))
        .thenAnswer((_) async => const Result.ok(null));
    await pumpScreen(tester);
    await type(tester, 'muse');

    await tester.tap(find.byTooltip('Add to this playlist'));
    await tester.pumpAndSettle();

    verify(() => playlists.addTracks('perm1', ['spotify:track:t2']))
        .called(1);
    verify(() => library.addToMain('spotify:track:t2')).called(1);
    expect(find.byTooltip('In this playlist'), findsOneWidget);
    expect(find.text('Added "Song t2" to "Road trip".'), findsOneWidget);
  });
}