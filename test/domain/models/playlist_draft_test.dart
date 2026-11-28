import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/playlist_draft.dart';
import 'package:playtier/domain/models/track.dart';

void main() {
  const track = Track(
    id: 't1',
    uri: 'spotify:track:t1',
    name: 'Song',
    artistIds: ['a1'],
    albumId: 'al',
    albumName: 'Album',
    duration: Duration(minutes: 3),
  );

  test('artist names are empty by default', () {
    expect(const PlaylistDraft(name: 'x', tracks: []).artistNames, isEmpty);
  });

  test('copyWith keeps the artist names unless replaced', () {
    const draft = PlaylistDraft(
      name: 'x',
      tracks: [track],
      artistNames: {'a1': 'Muse'},
    );

    final renamed = draft.copyWith(name: 'y');
    expect(renamed.name, 'y');
    expect(renamed.tracks, [track]);
    expect(renamed.artistNames, {'a1': 'Muse'});

    expect(
      draft.copyWith(artistNames: {'a1': 'Other'}).artistNames,
      {'a1': 'Other'},
    );
  });
}