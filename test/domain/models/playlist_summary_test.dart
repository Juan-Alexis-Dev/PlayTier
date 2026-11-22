import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/playlist_summary.dart';

PlaylistSummary summary(PlaylistType type) =>
    PlaylistSummary(id: 'p1', name: 'P', trackCount: 3, type: type);

void main() {
  test('liked, genre and artist playlists are virtual', () {
    expect(summary(PlaylistType.liked).isVirtual, isTrue);
    expect(summary(PlaylistType.genre).isVirtual, isTrue);
    expect(summary(PlaylistType.artist).isVirtual, isTrue);
  });

  test('main, permanent and spotify playlists are real', () {
    expect(summary(PlaylistType.main).isVirtual, isFalse);
    expect(summary(PlaylistType.permanent).isVirtual, isFalse);
    expect(summary(PlaylistType.spotify).isVirtual, isFalse);
  });

  test('equality and copyWith', () {
    expect(summary(PlaylistType.main), summary(PlaylistType.main));
    expect(
      summary(PlaylistType.main).copyWith(trackCount: 4),
      isNot(summary(PlaylistType.main)),
    );
  });
}