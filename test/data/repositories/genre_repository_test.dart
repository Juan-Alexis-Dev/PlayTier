import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/genre_repository.dart';
import 'package:playtier/data/services/lastfm/lastfm_service.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/local/tables.dart';
import 'package:playtier/data/services/musicbrainz/musicbrainz_service.dart';
import 'package:playtier/data/services/spotify/dto/spotify_artist_dto.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/result.dart';

class MockSpotify extends Mock implements SpotifyApiService {}

class MockLastFm extends Mock implements LastFmService {}

class MockMusicBrainz extends Mock implements MusicBrainzService {}

void main() {
  late AppDatabase db;
  late MockSpotify spotify;
  late MockLastFm lastFm;
  late MockMusicBrainz musicBrainz;
  late GenreRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    spotify = MockSpotify();
    lastFm = MockLastFm();
    musicBrainz = MockMusicBrainz();
    repo = GenreRepository(
      db: db,
      spotify: spotify,
      musicBrainz: musicBrainz,
      lastFm: lastFm,
    );

    // Defaults: no source has anything.
    when(() => spotify.getArtist(any())).thenAnswer(
      (i) async => SpotifyArtistDto(
        id: i.positionalArguments[0] as String,
        name: 'x',
      ),
    );
    when(() => lastFm.getArtistTopTags(any())).thenAnswer((_) async => []);
    when(() => musicBrainz.findArtistBySpotifyId(any()))
        .thenAnswer((_) async => null);
    when(() => musicBrainz.searchArtist(any(),
        minScore: any(named: 'minScore'))).thenAnswer((_) async => null);
    when(() => musicBrainz.getArtistGenres(any()))
        .thenAnswer((_) async => []);
  });
  tearDown(() => db.close());

  Future<void> insertArtist(String id, String name, {DateTime? fetchedAt}) {
    return db.into(db.artists).insert(
          ArtistsCompanion.insert(
            id: id,
            name: name,
            genresFetchedAt: Value(fetchedAt),
          ),
        );
  }

  Future<Map<String, GenreSource>> genresOf(String artistId) async {
    final rows = await (db.select(db.artistGenres)
          ..where((g) => g.artistId.equals(artistId)))
        .get();
    return {for (final row in rows) row.genre: row.source};
  }

  Future<DateTime?> fetchedAt(String artistId) async {
    final row = await (db.select(db.artists)
          ..where((a) => a.id.equals(artistId)))
        .getSingle();
    return row.genresFetchedAt;
  }

  void spotifyGenres(String id, List<String> genres) {
    when(() => spotify.getArtist(id)).thenAnswer(
      (_) async => SpotifyArtistDto(id: id, name: 'x', genres: genres),
    );
  }

  test('uses Spotify genres first and skips the other sources', () async {
    await insertArtist('a1', 'Muse');
    spotifyGenres('a1', ['Alternative Rock', 'modern rock']);

    expect(await repo.enrichMissing(), isA<Ok<int>>());

    expect(await genresOf('a1'), {
      'alternative rock': GenreSource.spotify,
      'modern rock': GenreSource.spotify,
    });
    expect(await fetchedAt('a1'), isNotNull);
    verifyNever(() => lastFm.getArtistTopTags(any()));
    verifyNever(() => musicBrainz.findArtistBySpotifyId(any()));
  });

  test('falls back to cleaned Last.fm tags', () async {
    await insertArtist('a1', 'Muse');
    when(() => lastFm.getArtistTopTags('Muse')).thenAnswer((_) async => [
          (name: 'Alternative Rock', count: 100),
          (name: 'seen live', count: 60),
          (name: 'muse', count: 50),
          (name: 'british', count: 30),
          (name: 'noise', count: 3),
        ]);

    await repo.enrichMissing();

    expect(await genresOf('a1'), {
      'alternative rock': GenreSource.lastFm,
      'british': GenreSource.lastFm,
    });
    verifyNever(() => musicBrainz.findArtistBySpotifyId(any()));
  });

  test('falls back to MusicBrainz through the Spotify id', () async {
    await insertArtist('a1', 'Muse');
    when(() => musicBrainz.findArtistBySpotifyId('a1'))
        .thenAnswer((_) async => 'mb1');
    when(() => musicBrainz.getArtistGenres('mb1')).thenAnswer((_) async => [
          (name: 'rock', count: 3),
          (name: 'Art Rock', count: 7),
        ]);

    await repo.enrichMissing();

    expect(await genresOf('a1'), {
      'art rock': GenreSource.musicBrainz,
      'rock': GenreSource.musicBrainz,
    });
    verifyNever(() =>
        musicBrainz.searchArtist(any(), minScore: any(named: 'minScore')));
  });

  test('searches MusicBrainz by name when the Spotify id is unknown',
      () async {
    await insertArtist('a1', 'Café Tacvba');
    when(() => musicBrainz.searchArtist('Café Tacvba',
        minScore: any(named: 'minScore'))).thenAnswer((_) async => 'mb2');
    when(() => musicBrainz.getArtistGenres('mb2'))
        .thenAnswer((_) async => [(name: 'rock en español', count: 2)]);

    await repo.enrichMissing();

    expect(await genresOf('a1'), {'rock en español': GenreSource.musicBrainz});
  });

  test('without a Last.fm key it goes from Spotify to MusicBrainz', () async {
    repo = GenreRepository(db: db, spotify: spotify, musicBrainz: musicBrainz);
    await insertArtist('a1', 'Muse');
    when(() => musicBrainz.findArtistBySpotifyId('a1'))
        .thenAnswer((_) async => 'mb1');
    when(() => musicBrainz.getArtistGenres('mb1'))
        .thenAnswer((_) async => [(name: 'rock', count: 1)]);

    await repo.enrichMissing();

    expect(await genresOf('a1'), {'rock': GenreSource.musicBrainz});
    verifyNever(() => lastFm.getArtistTopTags(any()));
  });

  test('an artist with no genres anywhere is cached and not asked again',
      () async {
    await insertArtist('a1', 'Unknown Band');

    final first = await repo.enrichMissing();
    final second = await repo.enrichMissing();

    expect((first as Ok<int>).value, 1);
    expect((second as Ok<int>).value, 0);
    expect(await genresOf('a1'), isEmpty);
    expect(await fetchedAt('a1'), isNotNull);
    verify(() => spotify.getArtist('a1')).called(1);
  });

  test('only pending artists are queried', () async {
    await insertArtist('done', 'Old', fetchedAt: DateTime(2026, 1, 1));
    await insertArtist('new', 'New');

    await repo.enrichMissing();

    verify(() => spotify.getArtist('new')).called(1);
    verifyNever(() => spotify.getArtist('done'));
  });

  test('an error stops the run; finished artists stay saved', () async {
    await insertArtist('a1', 'First');
    await insertArtist('a2', 'Second');
    spotifyGenres('a1', ['pop']);
    when(() => spotify.getArtist('a2'))
        .thenThrow(const SpotifyApiException(503, 'down'));

    final result = await repo.enrichMissing();

    expect(result, isA<Error<int>>());
    expect(await genresOf('a1'), {'pop': GenreSource.spotify});
    expect(await fetchedAt('a2'), isNull);
  });

  test('an artist removed during the lookup is not saved', () async {
    await insertArtist('a1', 'Muse');
    when(() => spotify.getArtist('a1')).thenAnswer((_) async {
      await (db.delete(db.artists)..where((a) => a.id.equals('a1'))).go();
      return const SpotifyArtistDto(id: 'a1', name: 'Muse', genres: ['rock']);
    });

    expect(await repo.enrichMissing(), isA<Ok<int>>());
    expect(await db.select(db.artistGenres).get(), isEmpty);
  });

  test('parallel calls share one run', () async {
    await insertArtist('a1', 'Muse');
    final gate = Completer<void>();
    when(() => spotify.getArtist('a1')).thenAnswer((_) async {
      await gate.future;
      return const SpotifyArtistDto(id: 'a1', name: 'Muse', genres: ['rock']);
    });

    final first = repo.enrichMissing();
    final second = repo.enrichMissing();
    gate.complete();

    expect(identical(first, second), isTrue);
    await first;
    verify(() => spotify.getArtist('a1')).called(1);
  });
}