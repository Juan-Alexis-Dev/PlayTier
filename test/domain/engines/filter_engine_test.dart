import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/filter_engine.dart';
import 'package:playtier/domain/models/filter_criteria.dart';
import 'package:playtier/domain/models/track.dart';

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
      albumName: album,
      duration: const Duration(minutes: 3),
      releaseDate: releaseDate,
      addedAt: addedAt,
    );

List<String> ids(List<Track> tracks) => tracks.map((t) => t.id).toList();

void main() {
  const genres = {
    'rockArtist': ['rock'],
    'popArtist': ['pop'],
    'mixArtist': ['rock', 'pop'],
    'jazzArtist': ['jazz'],
  };

  final rock = track('rock', artists: ['rockArtist']);
  final pop = track('pop', artists: ['popArtist']);
  final jazz = track('jazz', artists: ['jazzArtist']);
  final feat = track('feat', artists: ['jazzArtist', 'popArtist']);
  final unknown = track('unknown', artists: ['noGenres']);
  final all = [rock, pop, jazz, feat, unknown];

  List<String> run(FilterCriteria c, {Map<String, int> levels = const {}}) =>
      ids(FilterEngine.apply(all, c, genresByArtist: genres, levels: levels));

  test('empty criteria returns every track in order', () {
    expect(run(FilterCriteria.empty), ['rock', 'pop', 'jazz', 'feat', 'unknown']);
  });

  test('empty criteria returns a new list', () {
    final result = FilterEngine.apply(all, FilterCriteria.empty);
    expect(identical(result, all), isFalse);
  });

  group('genre', () {
    test('one genre', () {
      expect(run(FilterCriteria(genres: {'rock'})), ['rock']);
    });

    test('OR within the same type', () {
      expect(run(FilterCriteria(genres: {'rock', 'pop'})), ['rock', 'pop', 'feat']);
    });

    test('uses the genres of any artist of the track', () {
      expect(run(FilterCriteria(genres: {'jazz'})), ['jazz', 'feat']);
    });

    test('artists without genres never match a genre', () {
      expect(run(FilterCriteria(genres: {'rock', 'pop', 'jazz'})),
          isNot(contains('unknown')));
    });
  });

  test('artist filter includes featured artists (OR)', () {
    expect(run(FilterCriteria(artistIds: {'popArtist'})), ['pop', 'feat']);
    expect(
      run(FilterCriteria(artistIds: {'rockArtist', 'jazzArtist'})),
      ['rock', 'jazz', 'feat'],
    );
  });

  test('album filter', () {
    final tracks = [track('x', album: 'A'), track('y', album: 'B'), track('z', album: 'C')];
    final result = FilterEngine.apply(tracks, FilterCriteria(albumIds: {'A', 'C'}));
    expect(ids(result), ['x', 'z']);
  });

  group('level', () {
    test('tracks without a stored level are level 1', () {
      expect(run(FilterCriteria(levels: {1}), levels: {'rock': 3}),
          ['pop', 'jazz', 'feat', 'unknown']);
    });

    test('OR within levels', () {
      expect(run(FilterCriteria(levels: {3, 5}), levels: {'rock': 3, 'jazz': 5, 'pop': 2}),
          ['rock', 'jazz']);
    });
  });

  test('AND across types', () {
    // (rock OR pop) AND artist jazzArtist → only the track with both.
    expect(
      run(FilterCriteria(genres: {'rock', 'pop'}, artistIds: {'jazzArtist'})),
      ['feat'],
    );
    // A type with no match empties the result.
    expect(run(FilterCriteria(genres: {'rock'}, levels: {5})), isEmpty);
  });

  group('release year', () {
    final tracks = [
      track('y1990', releaseDate: '1990-05-01'),
      track('y2000', releaseDate: '2000'),
      track('y2010', releaseDate: '2010-03'),
      track('noDate'),
    ];
    List<String> years(FilterCriteria c) => ids(FilterEngine.apply(tracks, c));

    test('closed range is inclusive', () {
      expect(years(FilterCriteria(yearFrom: 1990, yearTo: 2000)), ['y1990', 'y2000']);
    });

    test('open bounds', () {
      expect(years(FilterCriteria(yearFrom: 2000)), ['y2000', 'y2010']);
      expect(years(FilterCriteria(yearTo: 2000)), ['y1990', 'y2000']);
    });

    test('tracks without a year do not match an active range', () {
      expect(years(FilterCriteria(yearTo: 3000)), isNot(contains('noDate')));
    });
  });

  group('date added', () {
    final tracks = [
      track('jan', addedAt: DateTime(2025, 1, 15)),
      track('feb', addedAt: DateTime(2025, 2, 1)),
      track('mar', addedAt: DateTime(2025, 3, 10)),
      track('noDate'),
    ];
    List<String> added(FilterCriteria c) => ids(FilterEngine.apply(tracks, c));

    test('closed range is inclusive', () {
      expect(
        added(FilterCriteria(addedFrom: DateTime(2025, 1, 15), addedTo: DateTime(2025, 2, 1))),
        ['jan', 'feb'],
      );
    });

    test('open bounds', () {
      expect(added(FilterCriteria(addedFrom: DateTime(2025, 2, 1))), ['feb', 'mar']);
      expect(added(FilterCriteria(addedTo: DateTime(2025, 1, 31))), ['jan']);
    });

    test('tracks without addedAt do not match an active range', () {
      expect(added(FilterCriteria(addedFrom: DateTime(2000))), isNot(contains('noDate')));
    });
  });
}