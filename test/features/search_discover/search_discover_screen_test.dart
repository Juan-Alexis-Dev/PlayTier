import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/discover_repository.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/search_repository.dart';
import 'package:playtier/domain/engines/virtual_playlists.dart';
import 'package:playtier/domain/models/playlist_draft.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/search_discover/discover_view_model.dart';
import 'package:playtier/features/search_discover/search_discover_screen.dart';
import 'package:playtier/features/search_discover/search_view_model.dart';
import 'package:provider/provider.dart';

class MockSearch extends Mock implements SearchRepository {}

class MockLibrary extends Mock implements LibraryRepository {}

class MockDiscover extends Mock implements DiscoverRepository {}

SearchResult result(String id, {bool inMain = false}) => SearchResult(
      track: Track(
        id: id,
        uri: 'spotify:track:$id',
        name: 'Song $id',
        artistIds: const ['a1', 'a2'],
        albumId: 'al1',
        albumName: 'Album',
        duration: const Duration(minutes: 3, seconds: 5),
      ),
      artistNames: const ['Muse', 'Guest'],
      inMain: inMain,
    );

void main() {
  late MockSearch search;
  late MockLibrary library;
  late MockDiscover discover;

  setUp(() {
    search = MockSearch();
    library = MockLibrary();
    discover = MockDiscover();
    when(() => discover.isAvailable).thenReturn(true);
    // Suggestions for own parameters.
    when(library.watchArtistPlaylists).thenAnswer(
      (_) => Stream.value(const <VirtualPlaylist>[
        (id: 'a1', name: 'Muse', trackCount: 3, coverUrls: []),
      ]),
    );
    when(library.watchGenrePlaylists).thenAnswer(
      (_) => Stream.value(const <VirtualPlaylist>[
        (id: 'rock', name: 'Rock', trackCount: 3, coverUrls: []),
      ]),
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SearchViewModel(
                search: search,
                library: library,
                debounce: Duration.zero,
              ),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  DiscoverViewModel(discover: discover, library: library)
                    ..init(),
            ),
          ],
          child: const SearchDiscoverScreen(),
        ),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    // The Spotify search bar (the own-parameters field is another one).
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Discover cards before searching', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Want new music? Try these:'), findsOneWidget);
    for (final mode in DiscoverViewModel.cardModes) {
      expect(find.text(mode.title), findsOneWidget);
    }
    // All four modes are ready.
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('Discover is replaced by a message without Last.fm',
      (tester) async {
    when(() => discover.isAvailable).thenReturn(false);
    await pumpScreen(tester);

    expect(find.textContaining('Last.fm API key'), findsOneWidget);
    expect(find.text('Want new music? Try these:'), findsNothing);
  });

  testWidgets('a mode with no new tracks shows a message', (tester) async {
    when(() => discover.newFromYourArtists(
          maxTracks: any(named: 'maxTracks'),
        )).thenAnswer(
      (_) async => const Result.ok(PlaylistDraft(name: 'x', tracks: [])),
    );
    await pumpScreen(tester);

    // The own-parameters card pushes the grid down.
    await tester.ensureVisible(find.text('New music from your artists'));
    await tester.tap(find.text('New music from your artists'));
    await tester.pumpAndSettle();

    expect(find.text(DiscoverViewModel.emptyText), findsOneWidget);
  });

  testWidgets('typing hides the Discover cards', (tester) async {
    when(() => search.search('muse', offset: 0))
        .thenAnswer((_) async => Result.ok([result('t1')]));
    await pumpScreen(tester);

    await type(tester, 'muse');

    expect(find.text('Want new music? Try these:'), findsNothing);
    expect(find.text('Song t1'), findsOneWidget);
  });

  testWidgets('shows results with "Add" or the in-main check',
      (tester) async {
    when(() => search.search('muse', offset: 0)).thenAnswer(
      (_) async => Result.ok([result('t1', inMain: true), result('t2')]),
    );
    await pumpScreen(tester);

    await type(tester, 'muse');

    expect(find.text('Song t1'), findsOneWidget);
    expect(find.text('Muse, Guest'), findsNWidgets(2));
    expect(find.text('3:05'), findsNWidgets(2));
    expect(find.byTooltip('In main playlist'), findsOneWidget);
    expect(find.byTooltip('Add to main playlist'), findsOneWidget);
  });

  testWidgets('tapping "Add" adds the track and shows a check',
      (tester) async {
    when(() => search.search('muse', offset: 0))
        .thenAnswer((_) async => Result.ok([result('t2')]));
    when(() => library.addToMain(any()))
        .thenAnswer((_) async => const Result.ok(null));
    await pumpScreen(tester);
    await type(tester, 'muse');

    await tester.tap(find.byTooltip('Add to main playlist'));
    await tester.pumpAndSettle();

    verify(() => library.addToMain('spotify:track:t2')).called(1);
    expect(find.byTooltip('In main playlist'), findsOneWidget);
    expect(find.textContaining('Added "Song t2"'), findsOneWidget);
  });

  testWidgets('no results shows a message', (tester) async {
    when(() => search.search('zzz', offset: 0))
        .thenAnswer((_) async => const Result.ok([]));
    await pumpScreen(tester);

    await type(tester, 'zzz');

    expect(find.text('No results for "zzz".'), findsOneWidget);
  });

  testWidgets('an error shows Retry, which searches again', (tester) async {
    when(() => search.search('muse', offset: 0))
        .thenAnswer((_) async => Result.error(Exception('offline')));
    await pumpScreen(tester);
    await type(tester, 'muse');

    expect(find.textContaining('Search failed'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    verify(() => search.search('muse', offset: 0)).called(2);
  });

  testWidgets('own parameters: pick a suggestion as a chip and run',
      (tester) async {
    when(() => discover.fromOwnParameters(
          artists: any(named: 'artists'),
          genres: any(named: 'genres'),
          maxTracks: any(named: 'maxTracks'),
        )).thenAnswer(
      (_) async => const Result.ok(PlaylistDraft(name: 'x', tracks: [])),
    );
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    final discoverButton = find.widgetWithText(FilledButton, 'Discover');
    expect(tester.widget<FilledButton>(discoverButton).onPressed, isNull);

    final field = find.descendant(
      of: find.byType(Card).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'mu');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Muse'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Muse'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<FilledButton>(discoverButton).onPressed, isNotNull);

    await tester.tap(discoverButton);
    await tester.pumpAndSettle();

    verify(() => discover.fromOwnParameters(
          artists: ['Muse'],
          genres: const [],
          maxTracks: any(named: 'maxTracks'),
        )).called(1);
    expect(find.text(DiscoverViewModel.emptyText), findsOneWidget);
  });

  testWidgets('removing the chip disables Discover again', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(Card).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'ro');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'rock'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove rock'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    final button = find.widgetWithText(FilledButton, 'Discover');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });
}