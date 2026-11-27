import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/playlist_repository.dart';
import 'package:playtier/data/repositories/search_repository.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/search_discover/search_view_model.dart';

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

/// A full page of results t<start>…t<start + pageSize - 1>.
List<SearchResult> page(int start) => [
      for (var i = start; i < start + SearchRepository.pageSize; i++)
        result('t$i'),
    ];

void main() {
  late MockSearch search;
  late MockLibrary library;
  late SearchViewModel vm;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    search = MockSearch();
    library = MockLibrary();
    vm = SearchViewModel(
      search: search,
      library: library,
      debounce: const Duration(milliseconds: 10),
    );
  });
  tearDown(() => vm.dispose());

  void stubSearch(String query, Result<List<SearchResult>> answer,
      {int offset = 0}) {
    when(() => search.search(query, offset: offset))
        .thenAnswer((_) async => answer);
  }

  test('typing searches once after the debounce', () async {
    stubSearch('muse', Result.ok([result('t1')]));

    vm.setQuery('m');
    vm.setQuery('mu');
    vm.setQuery('muse');
    expect(vm.results, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 30));

    verify(() => search.search('muse', offset: 0)).called(1);
    verifyNever(() => search.search('m', offset: 0));
    expect(vm.results.single.track.id, 't1');
    expect(vm.hasSearched, isTrue);
    expect(vm.loading, isFalse);
  });

  test('submit searches at once and trims the query', () async {
    stubSearch('muse', Result.ok([result('t1')]));

    vm.setQuery('  muse ');
    await vm.submit();

    expect(vm.results, hasLength(1));
    expect(vm.hasMore, isFalse);
  });

  test('a blank query clears the results', () async {
    stubSearch('muse', Result.ok([result('t1')]));
    vm.setQuery('muse');
    await vm.submit();

    vm.setQuery('  ');

    expect(vm.results, isEmpty);
    expect(vm.hasSearched, isFalse);
  });

  test('a late answer of an older search is ignored', () async {
    final slow = Completer<Result<List<SearchResult>>>();
    when(() => search.search('old', offset: 0))
        .thenAnswer((_) => slow.future);
    stubSearch('new', Result.ok([result('n1')]));

    vm.setQuery('old');
    final first = vm.submit();
    vm.setQuery('new');
    await vm.submit();
    slow.complete(Result.ok([result('o1')]));
    await first;

    expect(vm.results.single.track.id, 'n1');
  });

  test('errors show a message and no results', () async {
    stubSearch('muse', Result.error(Exception('offline')));

    vm.setQuery('muse');
    await vm.submit();

    expect(vm.results, isEmpty);
    expect(vm.errorMessage, isNotNull);
  });

  test('a full page enables "Load more", which appends the next page',
      () async {
    stubSearch('muse', Result.ok(page(0)));
    stubSearch(
      'muse',
      Result.ok([result('t9'), result('t10')]), // t9 is a repeat
      offset: SearchRepository.pageSize,
    );

    vm.setQuery('muse');
    await vm.submit();
    expect(vm.hasMore, isTrue);

    await vm.loadMore();

    expect(vm.results.map((r) => r.track.id).last, 't10');
    expect(vm.results, hasLength(SearchRepository.pageSize + 1));
    expect(vm.hasMore, isFalse);
  });

  test('add puts the track in main and marks it', () async {
    stubSearch('muse', Result.ok([result('t1'), result('t2')]));
    when(() => library.addToMain(any()))
        .thenAnswer((_) async => const Result.ok(null));
    vm.setQuery('muse');
    await vm.submit();

    final error = await vm.add(vm.results.first);

    expect(error, isNull);
    verify(() => library.addToMain('spotify:track:t1')).called(1);
    expect(vm.results.map((r) => r.inMain), [true, false]);
    expect(vm.isDone(vm.results.first), isTrue);
    expect(vm.isAdding('t1'), isFalse);
    expect(vm.addedCount, 1);
  });

  test('add does nothing for a track already in main', () async {
    final error = await vm.add(result('t1', inMain: true));

    expect(error, isNull);
    verifyNever(() => library.addToMain(any()));
  });

  test('a failed add keeps the track unmarked', () async {
    stubSearch('muse', Result.ok([result('t1')]));
    when(() => library.addToMain(any()))
        .thenAnswer((_) async => Result.error(Exception('403')));
    vm.setQuery('muse');
    await vm.submit();

    final error = await vm.add(vm.results.first);

    expect(error, isNotNull);
    expect(vm.results.single.inMain, isFalse);
    expect(vm.addedCount, 0);
  });

  group('with a target playlist (Add music)', () {
    late MockPlaylists playlists;
    late SearchViewModel target;

    setUp(() {
      playlists = MockPlaylists();
      target = SearchViewModel(
        search: search,
        library: library,
        playlists: playlists,
        targetPlaylistId: 'perm1',
        targetName: 'Road trip',
        targetTrackIds: const {'t1'},
      );
      when(() => playlists.addTracks(any(), any()))
          .thenAnswer((_) async => const Result.ok(null));
      when(() => library.addToMain(any()))
          .thenAnswer((_) async => const Result.ok(null));
    });
    tearDown(() => target.dispose());

    test('"done" means already in the target playlist', () {
      expect(target.hasTarget, isTrue);
      expect(target.isDone(result('t1')), isTrue);
      // In main but not in the playlist: can still be added.
      expect(target.isDone(result('t2', inMain: true)), isFalse);
    });

    test('adds to the playlist and to main when missing', () async {
      final error = await target.add(result('t2'));

      expect(error, isNull);
      verify(() => playlists.addTracks('perm1', ['spotify:track:t2']))
          .called(1);
      verify(() => library.addToMain('spotify:track:t2')).called(1);
      expect(target.isDone(result('t2')), isTrue);
      expect(target.addedCount, 1);
    });

    test('a track already in main is only added to the playlist', () async {
      final error = await target.add(result('t2', inMain: true));

      expect(error, isNull);
      verify(() => playlists.addTracks('perm1', ['spotify:track:t2']))
          .called(1);
      verifyNever(() => library.addToMain(any()));
    });

    test('a track already in the playlist is not added again', () async {
      final error = await target.add(result('t1'));

      expect(error, isNull);
      verifyNever(() => playlists.addTracks(any(), any()));
      verifyNever(() => library.addToMain(any()));
    });

    test('if the playlist fails, main is not touched', () async {
      when(() => playlists.addTracks(any(), any()))
          .thenAnswer((_) async => Result.error(Exception('403')));

      final error = await target.add(result('t2'));

      expect(error, contains('this playlist'));
      verifyNever(() => library.addToMain(any()));
      expect(target.isDone(result('t2')), isFalse);
    });

    test('if only main fails, the track stays in the playlist', () async {
      when(() => library.addToMain(any()))
          .thenAnswer((_) async => Result.error(Exception('500')));

      final error = await target.add(result('t2'));

      expect(error, contains('not to the main playlist'));
      expect(target.isDone(result('t2')), isTrue);
    });
  });
}