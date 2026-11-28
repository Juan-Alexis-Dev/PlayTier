import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/discover_repository.dart';
import 'package:playtier/data/services/lastfm/lastfm_service.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/spotify/dto/spotify_artist_dto.dart';
import 'package:playtier/data/services/spotify/dto/spotify_playlist_item_dto.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';

class MockSpotify extends Mock implements SpotifyApiService {}

class MockLastFm extends Mock implements LastFmService {}

SpotifyPlaylistItemDto dto(
  String id,
  String name, {
  List<String> artists = const ['Muse'],
}) =>
    SpotifyPlaylistItemDto(
      id: id,
      uri: 'spotify:track:$id',
      name: name,
      durationMs: 200000,
      albumId: 'al-$id',
      albumName: 'Album $id',
      releaseDate: '2009',
      coverUrl: 'https://img/$id',
      artists: [
        for (final (i, a) in artists.indexed)
          SpotifyArtistDto(id: 'ar-$id-$i', name: a),
      ],
    );

LastFmTrack lf(String name, [String artist = 'Muse']) =>
    (name: name, artist: artist);

void main() {
  late AppDatabase db;
  late MockSpotify api;
  late DiscoverRepository repo;

  /// Spotify answers by query: `track:"<name>" artist:"<artist>"`.
  late Map<String, List<SpotifyPlaylistItemDto>> spotify;

  String q(String name, [String artist = 'Muse']) =>
      'track:"$name" artist:"$artist"';

  void stubSearch() {
    when(() => api.searchTracks(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((invocation) async {
      final query = invocation.positionalArguments.first as String;
      return spotify[query] ?? const [];
    });
  }

  int searchCount() => verify(() => api.searchTracks(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      )).callCount;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = MockSpotify();
    repo = DiscoverRepository(api: api, db: db, lastFm: MockLastFm());
    spotify = {};
    stubSearch();

    // Main playlist: "Starlight" by Muse (id 'own').
    await db.into(db.tracks).insert(TracksCompanion.insert(
          id: 'own',
          uri: 'spotify:track:own',
          name: 'Starlight',
          albumId: 'al',
          albumName: 'Black Holes',
          durationMs: 240000,
          position: 0,
        ));
    await db
        .into(db.artists)
        .insert(ArtistsCompanion.insert(id: 'muse', name: 'Muse'));
    await db.into(db.trackArtists).insert(TrackArtistsCompanion.insert(
          trackId: 'own',
          artistId: 'muse',
          position: 0,
        ));
  });
  tearDown(() => db.close());

  List<SearchResult> okValue(Result<List<SearchResult>> result) =>
      (result as Ok<List<SearchResult>>).value;

  group('normalize', () {
    test('ignores case, punctuation, (…) and " - …" suffixes', () {
      expect(DiscoverRepository.normalize('Starlight'), 'starlight');
      expect(
        DiscoverRepository.normalize('Starlight - Remastered 2011'),
        'starlight',
      );
      expect(DiscoverRepository.normalize('Starlight (Live)'), 'starlight');
      expect(DiscoverRepository.normalize('Song [feat. X]'), 'song');
      expect(DiscoverRepository.normalize("Don't Stop"), 'dontstop');
      expect(DiscoverRepository.normalize('Café Tacvba'), 'cafétacvba');
    });

    test('keeps the text when nothing would be left', () {
      expect(DiscoverRepository.normalize('(Untitled)'), '(untitled)');
    });
  });

  test('isAvailable depends on Last.fm', () {
    expect(repo.isAvailable, isTrue);
    expect(
      DiscoverRepository(api: api, db: db, lastFm: null).isAvailable,
      isFalse,
    );
  });

  test('matches candidates in order and maps the tracks', () async {
    spotify[q('Uprising')] = [dto('t1', 'Uprising')];
    spotify[q('Creep', 'Radiohead')] = [
      dto('t2', 'Creep', artists: ['Radiohead']),
    ];

    final results = okValue(
      await repo.matchTracks([lf('Uprising'), lf('Creep', 'Radiohead')]),
    );

    expect(results.map((r) => r.track.id), ['t1', 't2']);
    expect(results.every((r) => !r.inMain), isTrue);
    final first = results.first;
    expect(first.track.uri, 'spotify:track:t1');
    expect(first.track.artistIds, ['ar-t1-0']);
    expect(first.artistNames, ['Muse']);
    expect(first.track.duration, const Duration(seconds: 200));
    expect(first.track.coverUrl, 'https://img/t1');
  });

  test('searches with field filters, 5 results and no quotes', () async {
    await repo.matchTracks([lf('Say "Hi"', 'The "Band"')]);

    verify(() => api.searchTracks(
          'track:"Say Hi" artist:"The Band"',
          limit: 5,
          offset: 0,
        )).called(1);
  });

  test('picks the first result with the same name and artist', () async {
    spotify[q('Uprising')] = [
      dto('cover', 'Uprising', artists: ['Cover Band']),
      dto('karaoke', 'Uprising (Karaoke)', artists: ['Karaoke Kings']),
      dto('real', 'Uprising', artists: ['Muse', 'Guest']),
    ];

    final results = okValue(await repo.matchTracks([lf('Uprising')]));
    expect(results.single.track.id, 'real');
  });

  test('skips candidates with no matching Spotify track', () async {
    spotify[q('Uprising')] = [
      dto('x', 'Something Else'),
      dto('y', 'Uprising', artists: ['Other']),
    ];

    expect(okValue(await repo.matchTracks([lf('Uprising')])), isEmpty);
  });

  test('a candidate already in main is skipped without searching', () async {
    final results = okValue(await repo.matchTracks([
      lf('STARLIGHT'),
      lf('Starlight - Remastered'),
    ]));

    expect(results, isEmpty);
    verifyNever(() => api.searchTracks(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ));
  });

  test('excludes Spotify tracks whose id is in main', () async {
    // Last.fm uses another name, but Spotify returns the owned track.
    spotify[q('Starlight Live')] = [dto('own', 'Starlight Live')];

    expect(okValue(await repo.matchTracks([lf('Starlight Live')])), isEmpty);
  });

  test('excludes an owned song found through a featured artist', () async {
    // Last.fm credits the guest; Spotify's main artist is Muse.
    spotify[q('Starlight', 'Guest')] = [
      dto('feat', 'Starlight', artists: ['Muse', 'Guest']),
    ];

    expect(
      okValue(await repo.matchTracks([lf('Starlight', 'Guest')])),
      isEmpty,
    );
  });

  test('repeated candidates (same normalized song) are searched once',
      () async {
    spotify[q('Uprising')] = [dto('t1', 'Uprising')];

    final results = okValue(await repo.matchTracks([
      lf('Uprising'),
      lf('uprising'),
      lf('Uprising - Live'),
    ]));

    expect(results.map((r) => r.track.id), ['t1']);
    expect(searchCount(), 1);
  });

  test('the same Spotify song from two candidates is kept once', () async {
    spotify[q('Uprising')] = [dto('t1', 'Uprising')];
    // Same id through another credited artist.
    spotify[q('Uprising', 'Guest')] = [
      dto('t1', 'Uprising', artists: ['Muse', 'Guest']),
    ];
    // Other album version (different id), same main artist.
    spotify[q('Uprising', 'Other')] = [
      dto('t1-single', 'Uprising', artists: ['Muse', 'Other']),
    ];

    final results = okValue(await repo.matchTracks([
      lf('Uprising'),
      lf('Uprising', 'Guest'),
      lf('Uprising', 'Other'),
    ]));

    expect(results.map((r) => r.track.id), ['t1']);
  });

  test('stops at maxTracks and does not search more batches', () async {
    final candidates = [for (var i = 0; i < 12; i++) lf('Song $i')];
    for (var i = 0; i < 12; i++) {
      spotify[q('Song $i')] = [dto('s$i', 'Song $i')];
    }

    final results =
        okValue(await repo.matchTracks(candidates, maxTracks: 3));

    expect(results.map((r) => r.track.id), ['s0', 's1', 's2']);
    expect(searchCount(), 5); // one batch of parallel searches
  });

  test('an empty candidate list returns an empty list', () async {
    expect(okValue(await repo.matchTracks([])), isEmpty);
  });

  test('a Spotify error returns Error', () async {
    when(() => api.searchTracks(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenThrow(const SpotifyApiException(500, 'boom'));

    expect(
      await repo.matchTracks([lf('Uprising')]),
      isA<Error<List<SearchResult>>>(),
    );
  });
}