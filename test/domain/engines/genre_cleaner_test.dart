import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/genre_cleaner.dart';

List<RawGenre> raw(Map<String, int> tags) =>
    [for (final e in tags.entries) (name: e.key, count: e.value)];

void main() {
  test('lower-cases, trims and collapses spaces', () {
    expect(
      GenreCleaner.clean(
        raw({'  Alternative   Rock ': 100, 'Indie': 50}),
        artistName: 'Muse',
      ),
      ['alternative rock', 'indie'],
    );
  });

  test('removes duplicates after normalizing', () {
    expect(
      GenreCleaner.clean(raw({'Rock': 100, 'rock ': 90}), artistName: 'Muse'),
      ['rock'],
    );
  });

  test('drops ignored tags and the artist name', () {
    expect(
      GenreCleaner.clean(
        raw({'seen live': 100, 'MUSE': 95, 'rock': 90, 'Male Vocalists': 80}),
        artistName: 'Muse',
      ),
      ['rock'],
    );
  });

  test('drops tags below minCount', () {
    expect(
      GenreCleaner.clean(
        raw({'rock': 100, 'pop': 10, 'jazz': 9}),
        artistName: 'Muse',
        minCount: 10,
      ),
      ['rock', 'pop'],
    );
  });

  test('sorts by count; ties keep their original order', () {
    expect(
      GenreCleaner.clean(
        raw({'b': 5, 'a': 20, 'c': 5, 'd': 5}),
        artistName: 'Muse',
      ),
      ['a', 'b', 'c', 'd'],
    );
  });

  test('keeps at most limit genres, counting only kept ones', () {
    final tags = raw({
      'seen live': 100,
      'g1': 90,
      'g2': 80,
      'g3': 70,
      'g4': 60,
      'g5': 50,
      'g6': 40,
    });
    expect(
      GenreCleaner.clean(tags, artistName: 'Muse'),
      ['g1', 'g2', 'g3', 'g4', 'g5'],
    );
    expect(GenreCleaner.clean(tags, artistName: 'Muse', limit: 2), [
      'g1',
      'g2',
    ]);
    expect(GenreCleaner.clean(tags, artistName: 'Muse', limit: null),
        hasLength(6));
  });

  test('empty names and empty input give an empty list', () {
    expect(GenreCleaner.clean(raw({'  ': 100}), artistName: 'Muse'), isEmpty);
    expect(GenreCleaner.clean(const [], artistName: 'Muse'), isEmpty);
  });
}