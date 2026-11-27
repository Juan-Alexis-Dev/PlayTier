import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/settings_repository.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/local/tables.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/engines/virtual_playlists.dart';

class MockSpotify extends Mock implements SpotifyApiService {}

class MockSettings extends Mock implements SettingsRepository {}

/// Short form of a card, easy to compare.
String card(VirtualPlaylist p) => '${p.name}:${p.trackCount}';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(
      api: MockSpotify(),
      db: db,
      settings: MockSettings(),
    );

    await db.batch((b) {
      b.insertAll(db.artists, [
        ArtistsCompanion.insert(id: 'a1', name: 'Muse'),
        ArtistsCompanion.insert(id: 'a2', name: 'Guest'),
      ]);
      b.insertAll(db.tracks, [
        for (final (i, id) in ['t1', 't2'].indexed)
          TracksCompanion.insert(
            id: id,
            uri: 'spotify:track:$id',
            name: id,
            albumId: 'al1',
            albumName: 'Album',
            durationMs: 1000,
            position: i,
          ),
      ]);
      b.insertAll(db.trackArtists, [
        TrackArtistsCompanion.insert(trackId: 't1', artistId: 'a1', position: 0),
        TrackArtistsCompanion.insert(trackId: 't1', artistId: 'a2', position: 1),
        TrackArtistsCompanion.insert(trackId: 't2', artistId: 'a1', position: 0),
      ]);
      b.insertAll(db.artistGenres, [
        ArtistGenresCompanion.insert(
          artistId: 'a1',
          genre: 'rock',
          source: GenreSource.lastFm,
        ),
      ]);
    });
  });
  tearDown(() => db.close());

  test('artist playlists come from the database', () async {
    final first = await repo.watchArtistPlaylists().first;
    expect(first.map(card), ['Muse:2', 'Guest:1']);
  });

  test('genre playlists update when enrichment saves a genre', () async {
    final events = StreamIterator(repo.watchGenrePlaylists());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current.map(card), ['Rock:2']);

    await db.into(db.artistGenres).insert(
          ArtistGenresCompanion.insert(
            artistId: 'a2',
            genre: 'pop',
            source: GenreSource.musicBrainz,
          ),
        );

    expect(await events.moveNext(), isTrue);
    expect(events.current.map(card), ['Rock:2', 'Pop:1']);
  });

  test('removing a track updates the counts (sync)', () async {
    final events = StreamIterator(repo.watchArtistPlaylists());
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);

    await (db.delete(db.tracks)..where((t) => t.id.equals('t1'))).go();

    expect(await events.moveNext(), isTrue);
    // Guest only had t1, so its playlist is gone.
    expect(events.current.map(card), ['Muse:1']);
  });
}