import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/filter_criteria.dart';
import 'package:playtier/domain/models/track.dart';
import 'package:playtier/features/filters/filter_view_model.dart';

Track track(
  String id, {
  List<String> artists = const ['a1'],
  String album = 'al1',
  String? releaseDate,
  DateTime? addedAt,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: artists,
      albumId: album,
      albumName: 'Album $album',
      duration: const Duration(minutes: 3),
      releaseDate: releaseDate,
      addedAt: addedAt,
    );

void main() {
  final tracks = [
    track('1', artists: ['rock'], releaseDate: '1990', addedAt: DateTime(2025, 1, 10)),
    track('2', artists: ['rock'], releaseDate: '2000', addedAt: DateTime(2025, 2, 10)),
    track('3', artists: ['pop'], album: 'al2', releaseDate: '2010'),
  ];

  FilterViewModel create({FilterCriteria? initial}) => FilterViewModel(
        tracks: tracks,
        genresByArtist: const {
          'rock': ['rock'],
          'pop': ['pop'],
        },
        artistNames: const {'rock': 'Rock Band', 'pop': 'Pop Star'},
        levels: const {'3': 4},
        initial: initial,
      );

  test('facets are ordered by frequency and labels are available', () {
    final vm = create();
    expect(vm.genres.first, (value: 'rock', count: 2));
    expect(vm.artists.first.value, 'rock');
    expect(vm.albumNames['al2'], 'Album al2');
    expect(vm.minYear, 1990);
    expect(vm.maxYear, 2010);
  });

  test('starts from the initial criteria and counts matches', () {
    expect(create().matchCount, 3);
    expect(create(initial: FilterCriteria(genres: {'pop'})).matchCount, 1);
  });

  test('toggling adds and removes a value and updates the count', () {
    final vm = create();
    var notified = 0;
    vm.addListener(() => notified++);

    vm.toggleGenre('rock');
    expect(vm.criteria.genres, {'rock'});
    expect(vm.matchCount, 2);

    vm.toggleArtist('pop'); // rock AND artist pop → nothing
    expect(vm.matchCount, 0);

    vm.toggleArtist('pop');
    vm.toggleGenre('rock');
    expect(vm.criteria.isEmpty, isTrue);
    expect(notified, 4);
  });

  test('level filter uses stored levels (missing = 1)', () {
    final vm = create()..toggleLevel(4);
    expect(vm.matchCount, 1);
    vm.toggleLevel(1);
    expect(vm.matchCount, 3);
  });

  test('selecting the whole year range clears the year filter', () {
    final vm = create()..setYearRange(1995, 2010);
    expect(vm.criteria.yearFrom, 1995);
    expect(vm.matchCount, 2);

    vm.setYearRange(1990, 2010);
    expect(vm.criteria.hasYearRange, isFalse);
  });

  test('date added includes the whole last day', () {
    final vm = create()
      ..setAddedRange(DateTime(2025, 1, 10, 15), DateTime(2025, 2, 10));
    expect(vm.criteria.addedFrom, DateTime(2025, 1, 10));
    expect(vm.criteria.addedTo, DateTime(2025, 2, 10, 23, 59, 59, 999));
    expect(vm.matchCount, 2);

    vm.setAddedRange(null, null);
    expect(vm.criteria.hasAddedRange, isFalse);
  });

  test('clear removes every filter', () {
    final vm = create(initial: FilterCriteria(genres: {'pop'}, levels: {4}))
      ..clear();
    expect(vm.criteria, FilterCriteria.empty);
    expect(vm.matchCount, 3);
  });
}