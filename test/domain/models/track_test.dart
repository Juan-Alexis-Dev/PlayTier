import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/track.dart';

Track track({
  String id = 't1',
  List<String> artistIds = const ['a1', 'a2'],
  String? releaseDate = '2020-05-17',
}) {
  return Track(
    id: id,
    uri: 'spotify:track:$id',
    name: 'Song',
    artistIds: artistIds,
    albumId: 'al1',
    albumName: 'Album',
    duration: const Duration(minutes: 3),
    releaseDate: releaseDate,
  );
}

void main() {
  group('releaseYear', () {
    test('reads the year from every Spotify precision', () {
      expect(track(releaseDate: '2020').releaseYear, 2020);
      expect(track(releaseDate: '2020-05').releaseYear, 2020);
      expect(track(releaseDate: '2020-05-17').releaseYear, 2020);
    });

    test('is null when the date is missing or invalid', () {
      expect(track(releaseDate: null).releaseYear, isNull);
      expect(track(releaseDate: '20').releaseYear, isNull);
      expect(track(releaseDate: 'abcd').releaseYear, isNull);
    });
  });

  group('equality', () {
    test('tracks with the same values are equal', () {
      expect(track(), track());
      expect(track().hashCode, track().hashCode);
    });

    test('artist list contents and order matter', () {
      expect(track(artistIds: ['a1', 'a2']), isNot(track(artistIds: ['a2', 'a1'])));
      expect(track(artistIds: ['a1']), isNot(track(artistIds: ['a1', 'a2'])));
    });
  });

  test('copyWith changes only the given fields', () {
    final original = track();
    final copy = original.copyWith(name: 'Other');

    expect(copy.name, 'Other');
    expect(copy.id, original.id);
    expect(copy.artistIds, original.artistIds);
    expect(copy, isNot(original));
  });
}