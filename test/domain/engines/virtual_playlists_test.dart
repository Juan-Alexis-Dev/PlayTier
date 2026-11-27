import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/engines/virtual_playlists.dart';
import 'package:playtier/domain/models/track.dart';

Track track(String id, List<String> artists, {String? cover}) => Track(
      id: id,
      uri: 'spotify:track:$id',
      name: id,
      artistIds: artists,
      albumId: 'al1',
      albumName: 'Album',
      duration: const Duration(minutes: 3),
      coverUrl: cover,
    );

/// Records compare lists by identity; maps get deep equality in `expect`.
Map<String, Object> asMap(VirtualPlaylist p) => {
      'id': p.id,
      'name': p.name,
      'trackCount': p.trackCount,
      'coverUrls': p.coverUrls,
    };

void main() {
  group('genres', () {
    test('one playlist per genre, ordered by track count', () {
      final tracks = [
        track('t1', ['a1'], cover: 'c1'),
        track('t2', ['a1'], cover: 'c2'),
        track('t3', ['a2'], cover: 'c3'),
      ];
      final result = VirtualPlaylists.genres(tracks, {
        'a1': ['rock'],
        'a2': ['pop', 'rock en español'],
      });

      expect(result.map(asMap), [
        {'id': 'rock', 'name': 'Rock', 'trackCount': 2, 'coverUrls': ['c1', 'c2']},
        {'id': 'pop', 'name': 'Pop', 'trackCount': 1, 'coverUrls': ['c3']},
        {
          'id': 'rock en español',
          'name': 'Rock en español',
          'trackCount': 1,
          'coverUrls': ['c3'],
        },
      ]);
    });

    test('a track counts once per genre even with two artists of it', () {
      final result = VirtualPlaylists.genres(
        [
          track('t1', ['a1', 'a2'], cover: 'c1'),
        ],
        {
          'a1': ['rock'],
          'a2': ['rock'],
        },
      );
      expect(result.single.trackCount, 1);
      expect(result.single.coverUrls, ['c1']);
    });

    test('tracks whose artists have no genres are left out', () {
      final result = VirtualPlaylists.genres([
        track('t1', ['a1']),
      ], {});
      expect(result, isEmpty);
    });
  });

  group('artists', () {
    test('one playlist per artist, featured artists included', () {
      final tracks = [
        track('t1', ['a1', 'a2'], cover: 'c1'),
        track('t2', ['a1'], cover: 'c2'),
      ];
      final result = VirtualPlaylists.artists(tracks, {
        'a1': 'Muse',
        'a2': 'Guest',
      });

      expect(result.map(asMap), [
        {'id': 'a1', 'name': 'Muse', 'trackCount': 2, 'coverUrls': ['c1', 'c2']},
        {'id': 'a2', 'name': 'Guest', 'trackCount': 1, 'coverUrls': ['c1']},
      ]);
    });

    test('an unknown name falls back to the id', () {
      final result = VirtualPlaylists.artists([
        track('t1', ['a9']),
      ], {});
      expect(result.single.name, 'a9');
    });
  });

  test('covers: distinct, playlist order, at most 4, nulls skipped', () {
    final tracks = [
      for (final (i, cover) in ['c1', 'c1', null, 'c2', 'c3', 'c4', 'c5']
          .indexed)
        track('t$i', ['a1'], cover: cover),
    ];
    final result = VirtualPlaylists.artists(tracks, {'a1': 'Muse'});
    expect(result.single.coverUrls, ['c1', 'c2', 'c3', 'c4']);
    expect(result.single.trackCount, 7);
  });
}