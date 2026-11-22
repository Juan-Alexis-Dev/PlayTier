import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/sort_engine.dart';
import 'package:playtier/domain/models/sort_option.dart';
import 'package:playtier/domain/models/track.dart';

Track track(
  String id, {
  String? name,
  List<String> artists = const ['a1'],
  String album = 'Album',
  int seconds = 180,
  DateTime? addedAt,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: name ?? id,
      artistIds: artists,
      albumId: album,
      albumName: album,
      duration: Duration(seconds: seconds),
      addedAt: addedAt,
    );

List<String> ids(List<Track> tracks) => tracks.map((t) => t.id).toList();

const asc = SortDirection.ascending;
const desc = SortDirection.descending;

void main() {
  test('returns a new list and does not change the input', () {
    final input = [track('b'), track('a')];
    final result = SortEngine.sort(input, const SortOption(SortField.title, asc));
    expect(ids(result), ['a', 'b']);
    expect(ids(input), ['b', 'a']);
  });

  test('empty list', () {
    expect(SortEngine.sort([], SortOption.defaultOption), isEmpty);
  });

  group('date added', () {
    final tracks = [
      track('feb', addedAt: DateTime(2025, 2, 1)),
      track('none'),
      track('jan', addedAt: DateTime(2025, 1, 1)),
      track('mar', addedAt: DateTime(2025, 3, 1)),
    ];

    test('newest first by default, nulls last', () {
      expect(ids(SortEngine.sort(tracks, SortOption.defaultOption)),
          ['mar', 'feb', 'jan', 'none']);
    });

    test('oldest first, nulls still last', () {
      expect(ids(SortEngine.sort(tracks, const SortOption(SortField.dateAdded, asc))),
          ['jan', 'feb', 'mar', 'none']);
    });
  });

  test('title ignores case', () {
    final tracks = [track('1', name: 'beta'), track('2', name: 'Alpha'), track('3', name: 'Gamma')];
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.title, asc))), ['2', '1', '3']);
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.title, desc))), ['3', '1', '2']);
  });

  test('artist uses the name of the first artist', () {
    const names = {'z': 'Zoe', 'a': 'abba', 'm': 'Muse'};
    final tracks = [
      track('t1', artists: ['z']),
      track('t2', artists: ['m', 'a']),
      track('t3', artists: ['a', 'z']),
      track('t4', artists: ['unknown']),
    ];
    final result = SortEngine.sort(
      tracks,
      const SortOption(SortField.artist, asc),
      artistNames: names,
    );
    expect(ids(result), ['t4', 't3', 't2', 't1']);
  });

  test('album', () {
    final tracks = [track('1', album: 'Ok'), track('2', album: 'abbey'), track('3', album: 'Nevermind')];
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.album, asc))), ['2', '3', '1']);
  });

  test('duration', () {
    final tracks = [track('mid', seconds: 200), track('short', seconds: 90), track('long', seconds: 400)];
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.duration, asc))),
        ['short', 'mid', 'long']);
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.duration, desc))),
        ['long', 'mid', 'short']);
  });

  test('like level, missing tracks are level 1', () {
    final tracks = [track('l1'), track('l5'), track('l3')];
    final result = SortEngine.sort(
      tracks,
      const SortOption(SortField.likeLevel, desc),
      levels: {'l5': 5, 'l3': 3},
    );
    expect(ids(result), ['l5', 'l3', 'l1']);
  });

  test('stable: equal values keep the original order in both directions', () {
    final tracks = [
      track('a', seconds: 100),
      track('x1', seconds: 200),
      track('x2', seconds: 200),
      track('x3', seconds: 200),
      track('b', seconds: 300),
    ];
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.duration, asc))),
        ['a', 'x1', 'x2', 'x3', 'b']);
    expect(ids(SortEngine.sort(tracks, const SortOption(SortField.duration, desc))),
        ['b', 'x1', 'x2', 'x3', 'a']);
  });
}