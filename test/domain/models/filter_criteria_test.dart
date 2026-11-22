import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/filter_criteria.dart';

void main() {
  test('empty has no active filters', () {
    expect(FilterCriteria.empty.isEmpty, isTrue);
    expect(FilterCriteria.empty.activeCount, 0);
  });

  test('activeCount counts filter types, not values', () {
    final criteria = FilterCriteria(
      genres: {'rock', 'pop'},
      artistIds: {'a1'},
      yearFrom: 2000,
    );
    expect(criteria.activeCount, 3);
    expect(criteria.isNotEmpty, isTrue);
  });

  test('sets cannot be modified', () {
    final criteria = FilterCriteria(genres: {'rock'});
    expect(() => criteria.genres.add('pop'), throwsUnsupportedError);
  });

  test('changing the original set does not change the criteria', () {
    final genres = {'rock'};
    final criteria = FilterCriteria(genres: genres);
    genres.add('pop');
    expect(criteria.genres, {'rock'});
  });

  test('copyWith keeps ranges', () {
    final criteria = FilterCriteria(yearFrom: 1990, yearTo: 1999)
        .copyWith(levels: {3, 4});
    expect(criteria.levels, {3, 4});
    expect(criteria.yearFrom, 1990);
    expect(criteria.yearTo, 1999);
  });

  test('withYearRange and withAddedRange can clear bounds', () {
    final added = DateTime(2024, 1, 1);
    final criteria = FilterCriteria(yearFrom: 1990, addedFrom: added)
        .withYearRange(null, null);
    expect(criteria.hasYearRange, isFalse);
    expect(criteria.addedFrom, added);
    expect(criteria.withAddedRange(null, null).isEmpty, isTrue);
  });

  test('equality ignores set order', () {
    expect(
      FilterCriteria(genres: {'rock', 'pop'}),
      FilterCriteria(genres: {'pop', 'rock'}),
    );
    expect(
      FilterCriteria(genres: {'rock', 'pop'}).hashCode,
      FilterCriteria(genres: {'pop', 'rock'}).hashCode,
    );
    expect(FilterCriteria(genres: {'rock'}), isNot(FilterCriteria.empty));
  });

  test('invalid values fail in debug mode', () {
    expect(() => FilterCriteria(levels: {0}), throwsAssertionError);
    expect(() => FilterCriteria(levels: {6}), throwsAssertionError);
    expect(
      () => FilterCriteria(yearFrom: 2020, yearTo: 2010),
      throwsAssertionError,
    );
    expect(
      () => FilterCriteria(
        addedFrom: DateTime(2025),
        addedTo: DateTime(2024),
      ),
      throwsAssertionError,
    );
  });
}