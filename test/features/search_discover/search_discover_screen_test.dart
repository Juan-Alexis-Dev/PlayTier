import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/search_repository.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/search_discover/search_discover_screen.dart';
import 'package:playtier/features/search_discover/search_view_model.dart';
import 'package:provider/provider.dart';

class MockSearch extends Mock implements SearchRepository {}

class MockLibrary extends Mock implements LibraryRepository {}

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

  setUp(() {
    search = MockSearch();
    library = MockLibrary();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => SearchViewModel(
            search: search,
            library: library,
            debounce: Duration.zero,
          ),
          child: const SearchDiscoverScreen(),
        ),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the hint before searching', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('Search Spotify by track'), findsOneWidget);
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
}