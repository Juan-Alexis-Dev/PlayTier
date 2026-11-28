import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/discover_repository.dart';
import 'package:playtier/domain/models/discover_mode.dart';
import 'package:playtier/domain/models/playlist_draft.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/search_discover/discover_view_model.dart';

class MockDiscover extends Mock implements DiscoverRepository {}

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
  late DiscoverViewModel vm;

  setUp(() {
    discover = MockDiscover();
    when(() => discover.isAvailable).thenReturn(true);
    vm = DiscoverViewModel(discover: discover);
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
    expect(vm.isReady(DiscoverMode.toTry), isFalse);
    expect(vm.canRun(DiscoverMode.toTry), isFalse);
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

  test('a mode that is not ready does nothing', () async {
    expect(await vm.run(DiscoverMode.toTry), isNull);
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
}