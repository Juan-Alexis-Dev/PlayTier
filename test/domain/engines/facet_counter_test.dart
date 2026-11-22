import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/facet_counter.dart';
import 'package:playtier/domain/models/track.dart';

Track track(
  String id, {
  List<String> artists = const ['a1'],
  String albumId = 'al1',
  String? albumName,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: artists,
      albumId: albumId,
      albumName: albumName ?? albumId,
      duration: const Duration(minutes: 3),
    );

List<String> values(List<FacetCount> facets) =>
    facets.map((f) => f.value).toList();

void main() {
  test('empty list gives no facets', () {
    expect(FacetCounter.genres([], {}), isEmpty);
    expect(FacetCounter.artists([]), isEmpty);
    expect(FacetCounter.albums([]), isEmpty);
  });

  group('genres', () {
    const genres = {
      'rockArtist': ['rock'],
      'popArtist': ['pop'],
      'mixArtist': ['rock', 'pop'],
      'jazzArtist': ['jazz'],
    };

    test('ordered by frequency', () {
      final tracks = [
        track('1', artists: ['rockArtist']),
        track('2', artists: ['rockArtist']),
        track('3', artists: ['popArtist']),
        track('4', artists: ['mixArtist']),
        track('5', artists: ['jazzArtist']),
      ];
      final result = FacetCounter.genres(tracks, genres);
      expect(result, [
        (value: 'rock', count: 3),
        (value: 'pop', count: 2),
        (value: 'jazz', count: 1),
      ]);
    });

    test('a track counts once per genre even if two artists share it', () {
      final tracks = [track('1', artists: ['rockArtist', 'mixArtist'])];
      expect(FacetCounter.genres(tracks, genres), [
        (value: 'pop', count: 1),
        (value: 'rock', count: 1),
      ]);
    });

    test('artists without genres add nothing', () {
      final tracks = [track('1', artists: ['unknown'])];
      expect(FacetCounter.genres(tracks, genres), isEmpty);
    });
  });

  group('artists', () {
    test('featured artists are counted', () {
      final tracks = [
        track('1', artists: ['a', 'b']),
        track('2', artists: ['b']),
        track('3', artists: ['c']),
      ];
      expect(FacetCounter.artists(tracks), [
        (value: 'b', count: 2),
        (value: 'a', count: 1),
        (value: 'c', count: 1),
      ]);
    });

    test('repeated artist id in one track counts once', () {
      final tracks = [track('1', artists: ['a', 'a'])];
      expect(FacetCounter.artists(tracks), [(value: 'a', count: 1)]);
    });

    test('ties are sorted by name ignoring case', () {
      final tracks = [
        track('1', artists: ['id1']),
        track('2', artists: ['id2']),
        track('3', artists: ['id3']),
      ];
      final result = FacetCounter.artists(
        tracks,
        artistNames: {'id1': 'Zoe', 'id2': 'abba', 'id3': 'Muse'},
      );
      expect(values(result), ['id2', 'id3', 'id1']);
    });
  });

  group('albums', () {
    test('ordered by frequency, ties by album name', () {
      final tracks = [
        track('1', albumId: 'x', albumName: 'Ok Computer'),
        track('2', albumId: 'y', albumName: 'Abbey Road'),
        track('3', albumId: 'z', albumName: 'Nevermind'),
        track('4', albumId: 'z', albumName: 'Nevermind'),
      ];
      final result = FacetCounter.albums(tracks);
      expect(result.first, (value: 'z', count: 2));
      expect(values(result), ['z', 'y', 'x']);
    });
  });
}