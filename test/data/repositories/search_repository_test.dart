import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/search_repository.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/spotify/dto/spotify_artist_dto.dart';
import 'package:playtier/data/services/spotify/dto/spotify_playlist_item_dto.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';

class MockSpotify extends Mock implements SpotifyApiService {}

SpotifyPlaylistItemDto dto(String id) => SpotifyPlaylistItemDto(
      id: id,
      uri: 'spotify:track:$id',
      name: 'Song $id',
      durationMs: 180000,
      albumId: 'al1',
      albumName: 'Album',
      releaseDate: '2021-03-04',
      coverUrl: 'https://img/$id',
      artists: const [
        SpotifyArtistDto(id: 'a1', name: 'Muse'),
        SpotifyArtistDto(id: 'a2', name: 'Guest'),
      ],
    );

void main() {
  late AppDatabase db;
  late MockSpotify api;
  late SearchRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = MockSpotify();
    repo = SearchRepository(api: api, db: db);

    // 't1' is already in the main playlist.
    await db.into(db.tracks).insert(
          TracksCompanion.insert(
            id: 't1',
            uri: 'spotify:track:t1',
            name: 'Song t1',
            albumId: 'al1',
            albumName: 'Album',
            durationMs: 180000,
            position: 0,
          ),
        );
  });
  tearDown(() => db.close());

  List<SearchResult> okValue(Result<List<SearchResult>> result) =>
      (result as Ok<List<SearchResult>>).value;

  test('maps results and flags tracks already in main', () async {
    when(() => api.searchTracks('muse', offset: 0))
        .thenAnswer((_) async => [dto('t1'), dto('t2')]);

    final results = okValue(await repo.search('  muse '));

    expect(results.map((r) => (r.track.id, r.inMain)), [
      ('t1', true),
      ('t2', false),
    ]);
    final first = results.first;
    expect(first.track.uri, 'spotify:track:t1');
    expect(first.track.artistIds, ['a1', 'a2']);
    expect(first.artistNames, ['Muse', 'Guest']);
    expect(first.track.duration, const Duration(minutes: 3));
    expect(first.track.releaseYear, 2021);
    expect(first.track.coverUrl, 'https://img/t1');
  });

  test('passes the offset to Spotify', () async {
    when(() => api.searchTracks('muse', offset: 10))
        .thenAnswer((_) async => [dto('t3')]);

    final results = okValue(await repo.search('muse', offset: 10));

    expect(results.single.track.id, 't3');
    expect(results.single.inMain, isFalse);
  });

  test('blank query returns an empty list without calling Spotify', () async {
    final results = okValue(await repo.search('   '));

    expect(results, isEmpty);
    verifyNever(
      () => api.searchTracks(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    );
  });

  test('no results returns an empty list', () async {
    when(() => api.searchTracks('zzz', offset: 0)).thenAnswer((_) async => []);

    expect(okValue(await repo.search('zzz')), isEmpty);
  });

  test('API errors become Result.error', () async {
    when(() => api.searchTracks('muse', offset: 0))
        .thenThrow(const SpotifyApiException(429, 'rate limited'));

    final result = await repo.search('muse');

    expect(result, isA<Error<List<SearchResult>>>());
  });
}