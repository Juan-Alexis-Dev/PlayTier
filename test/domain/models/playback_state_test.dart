import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/domain/models/playback_state.dart';

final readAt = DateTime(2026, 1, 1, 12);

PlaybackState state({bool playing = true, int positionSeconds = 30}) =>
    PlaybackState(
      trackUri: 'spotify:track:abc',
      trackName: 'Song',
      artistNames: const ['Artist'],
      albumName: 'Album',
      duration: const Duration(minutes: 3),
      position: Duration(seconds: positionSeconds),
      isPlaying: playing,
      updatedAt: readAt,
    );

void main() {
  test('trackId comes from the URI', () {
    expect(state().trackId, 'abc');
  });

  test('positionAt grows while playing', () {
    final later = readAt.add(const Duration(seconds: 10));
    expect(state().positionAt(later), const Duration(seconds: 40));
  });

  test('positionAt does not move while paused', () {
    final later = readAt.add(const Duration(seconds: 10));
    expect(state(playing: false).positionAt(later), const Duration(seconds: 30));
  });

  test('positionAt is capped at the track duration', () {
    final later = readAt.add(const Duration(minutes: 10));
    expect(state().positionAt(later), const Duration(minutes: 3));
  });
}