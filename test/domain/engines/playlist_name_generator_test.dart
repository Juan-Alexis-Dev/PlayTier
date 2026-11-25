import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/playlist_name_generator.dart';
import 'package:playtier/domain/models/filter_criteria.dart';

String name(
  FilterCriteria criteria, {
  Map<String, String> artists = const {},
  Map<String, String> albums = const {},
}) =>
    PlaylistNameGenerator.generate(
      criteria,
      artistNames: artists,
      albumNames: albums,
    );

void main() {
  test('no filters gives the fallback', () {
    expect(name(FilterCriteria.empty), PlaylistNameGenerator.fallback);
  });

  test('genres in title case, joined with +', () {
    expect(name(FilterCriteria(genres: {'rock', 'hip hop'})), 'Rock + Hip Hop');
  });

  test('more than two values become "+ N more"', () {
    expect(
      name(FilterCriteria(genres: {'rock', 'pop', 'jazz', 'blues'})),
      'Rock + Pop + 2 more',
    );
  });

  test('types are joined with · in a fixed order', () {
    final criteria = FilterCriteria(
      levels: {5},
      artistIds: {'a1'},
      genres: {'rock', 'pop'},
      albumIds: {'al1'},
    );
    expect(
      name(criteria, artists: {'a1': 'Artist X'}, albums: {'al1': 'Nevermind'}),
      'Rock + Pop · Artist X · Nevermind · Level 5',
    );
  });

  test('unknown artist and album ids are skipped', () {
    expect(name(FilterCriteria(artistIds: {'missing'})), PlaylistNameGenerator.fallback);
    expect(
      name(FilterCriteria(artistIds: {'a1', 'missing'}), artists: {'a1': 'Muse'}),
      'Muse',
    );
  });

  test('levels are sorted', () {
    expect(name(FilterCriteria(levels: {5, 3, 4})), 'Levels 3, 4, 5');
  });

  group('release year', () {
    test('closed range', () {
      expect(name(FilterCriteria(yearFrom: 1990, yearTo: 1999)), '1990–1999');
    });

    test('open bounds and single year', () {
      expect(name(FilterCriteria(yearFrom: 2000)), 'From 2000');
      expect(name(FilterCriteria(yearTo: 1999)), 'Until 1999');
      expect(name(FilterCriteria(yearFrom: 2005, yearTo: 2005)), '2005');
    });
  });

  group('date added', () {
    test('closed range', () {
      final criteria = FilterCriteria(
        addedFrom: DateTime(2025, 1, 5),
        addedTo: DateTime(2025, 2, 10, 23, 59, 59, 999),
      );
      expect(name(criteria), 'Added 2025-01-05 – 2025-02-10');
    });

    test('open bounds and single day', () {
      expect(name(FilterCriteria(addedFrom: DateTime(2025, 3, 1))),
          'Added since 2025-03-01');
      expect(name(FilterCriteria(addedTo: DateTime(2025, 3, 1))),
          'Added until 2025-03-01');
      expect(
        name(FilterCriteria(
          addedFrom: DateTime(2025, 3, 1),
          addedTo: DateTime(2025, 3, 1, 23, 59),
        )),
        'Added 2025-03-01',
      );
    });
  });

  test('long names are cut with …', () {
    final artists = {
      'a1': 'A' * 60,
      'a2': 'B' * 60,
    };
    final result = name(FilterCriteria(artistIds: {'a1', 'a2'}), artists: artists);
    expect(result.length, PlaylistNameGenerator.maxLength);
    expect(result, endsWith('…'));
  });
}