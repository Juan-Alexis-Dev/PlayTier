import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/discover_repository.dart';
import 'package:playtier/data/services/lastfm/lastfm_api_exception.dart';
import 'package:playtier/data/services/lastfm/lastfm_service.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/local/tables.dart';
import 'package:playtier/data/services/spotify/dto/spotify_artist_dto.dart';
import 'package:playtier/data/services/spotify/dto/spotify_playlist_item_dto.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/playlist_draft.dart';
import 'package:playtier/domain/models/result.dart';
import 'package:playtier/domain/models/search_result.dart';
import 'package:playtier/domain/models/track.dart';

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

/// Shufflers for tests: no change, or reversed (a "different" random).
void keepOrder(List<Object?> list) {}

void reverseOrder(List<Object?> list) =>
    list.setAll(0, list.reversed.toList());

void main() {
  late AppDatabase db;
  late MockSpotify api;
  late MockLastFm lastFm;
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
    lastFm = MockLastFm();
    // Keeps every order, so results are predictable.
    repo = DiscoverRepository(
      api: api,
      db: db,
      lastFm: lastFm,
      shuffle: keepOrder,
    );
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

  test('interleave takes one item of each list per round', () {
    expect(
      DiscoverRepository.interleave([
        ['a1', 'a2'],
        ['b1'],
        <String>[],
        ['c1', 'c2', 'c3'],
      ]),
      ['a1', 'b1', 'c1', 'a2', 'c2', 'c3'],
    );
    expect(DiscoverRepository.interleave(<List<int>>[]), isEmpty);
  });

  group('newFromYourArtists', () {
    Future<void> addTrack(String id, String name, List<String> artistIds) async {
      await db.into(db.tracks).insert(TracksCompanion.insert(
            id: id,
            uri: 'spotify:track:$id',
            name: name,
            albumId: 'al',
            albumName: 'Album',
            durationMs: 200000,
            position: 1,
          ));
      for (final (i, artistId) in artistIds.indexed) {
        await db.into(db.trackArtists).insert(TrackArtistsCompanion.insert(
              trackId: id,
              artistId: artistId,
              position: i,
            ));
      }
    }

    void stubTopTracks(Map<String, List<LastFmTrack>> byArtist) {
      when(() => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((invocation) async {
        final artist = invocation.positionalArguments.first as String;
        return byArtist[artist] ?? const [];
      });
    }

    setUp(() async {
      // Library: Radiohead 2 tracks, Muse 1 (setUp above), Guest only
      // as a featured artist (not a main artist).
      await db.into(db.artists).insert(
            ArtistsCompanion.insert(id: 'rh', name: 'Radiohead'),
          );
      await db.into(db.artists).insert(
            ArtistsCompanion.insert(id: 'guest', name: 'Guest'),
          );
      await addTrack('rh1', 'Airbag', ['rh', 'guest']);
      await addTrack('rh2', 'No Surprises', ['rh', 'guest']);
    });

    PlaylistDraft draftOf(Result<PlaylistDraft> result) =>
        (result as Ok<PlaylistDraft>).value;

    test('asks Last.fm for the main artists, most tracks first', () async {
      stubTopTracks({});

      await repo.newFromYourArtists();

      final calls = verify(() => lastFm.getArtistTopTracks(
            captureAny(),
            limit: DiscoverRepository.tracksPerArtist,
          )).captured;
      expect(calls, ['Radiohead', 'Muse']);
    });

    test('mixes artists, skips owned tracks and names the draft', () async {
      stubTopTracks({
        'Radiohead': [lf('Creep', 'Radiohead'), lf('Karma Police', 'Radiohead')],
        'Muse': [lf('Starlight'), lf('Uprising')], // Starlight is owned
      });
      spotify[q('Creep', 'Radiohead')] = [
        dto('creep', 'Creep', artists: ['Radiohead']),
      ];
      spotify[q('Karma Police', 'Radiohead')] = [
        dto('karma', 'Karma Police', artists: ['Radiohead']),
      ];
      spotify[q('Uprising')] = [dto('upr', 'Uprising')];

      final draft = draftOf(await repo.newFromYourArtists());

      expect(draft.name, 'New music from your artists');
      expect(draft.tracks.map((t) => t.id), ['creep', 'upr', 'karma']);
    });

    test('respects maxTracks', () async {
      stubTopTracks({
        'Radiohead': [lf('Creep', 'Radiohead')],
        'Muse': [lf('Uprising')],
      });
      spotify[q('Creep', 'Radiohead')] = [
        dto('creep', 'Creep', artists: ['Radiohead']),
      ];
      spotify[q('Uprising')] = [dto('upr', 'Uprising')];

      final draft = draftOf(await repo.newFromYourArtists(maxTracks: 1));
      expect(draft.tracks.map((t) => t.id), ['creep']);
    });

    test('another shuffle gives other artists and track order', () async {
      final shuffled = DiscoverRepository(
        api: api,
        db: db,
        lastFm: lastFm,
        shuffle: reverseOrder,
      );
      stubTopTracks({
        'Radiohead': [
          lf('Creep', 'Radiohead'),
          lf('Karma Police', 'Radiohead'),
        ],
        'Muse': [lf('Uprising')],
      });
      spotify[q('Creep', 'Radiohead')] = [
        dto('creep', 'Creep', artists: ['Radiohead']),
      ];
      spotify[q('Karma Police', 'Radiohead')] = [
        dto('karma', 'Karma Police', artists: ['Radiohead']),
      ];
      spotify[q('Uprising')] = [dto('upr', 'Uprising')];

      final draft = draftOf(await shuffled.newFromYourArtists());

      // Artists picked as [Muse, Radiohead]; Radiohead's tracks reversed.
      expect(draft.tracks.map((t) => t.id), ['upr', 'karma', 'creep']);
    });

    test('an empty library returns an empty draft without calls', () async {
      await db.delete(db.trackArtists).go();
      await db.delete(db.tracks).go();
      stubTopTracks({});

      final draft = draftOf(await repo.newFromYourArtists());

      expect(draft.tracks, isEmpty);
      verifyNever(
        () => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')),
      );
    });

    test('a Last.fm error returns Error', () async {
      when(() => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')))
          .thenThrow(const LastFmApiException(429, 'Rate limit', errorCode: 29));

      expect(
        await repo.newFromYourArtists(),
        isA<Error<PlaylistDraft>>(),
      );
    });

    test('without Last.fm returns Error and calls nothing', () async {
      final noLastFm = DiscoverRepository(api: api, db: db, lastFm: null);

      expect(
        await noLastFm.newFromYourArtists(),
        isA<Error<PlaylistDraft>>(),
      );
      verifyNever(() => api.searchTracks(
            any(),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ));
    });
  });

  group('newFromYourGenres', () {
    Future<void> addTrack(String id, String name, List<String> artistIds) async {
      await db.into(db.tracks).insert(TracksCompanion.insert(
            id: id,
            uri: 'spotify:track:$id',
            name: name,
            albumId: 'al',
            albumName: 'Album',
            durationMs: 200000,
            position: 1,
          ));
      for (final (i, artistId) in artistIds.indexed) {
        await db.into(db.trackArtists).insert(TrackArtistsCompanion.insert(
              trackId: id,
              artistId: artistId,
              position: i,
            ));
      }
    }

    Future<void> addArtist(String id, String name, List<String> genres) async {
      await db.into(db.artists).insert(
            ArtistsCompanion.insert(id: id, name: name),
            mode: InsertMode.insertOrIgnore,
          );
      for (final genre in genres) {
        await db.into(db.artistGenres).insert(ArtistGenresCompanion.insert(
              artistId: id,
              genre: genre,
              source: GenreSource.lastFm,
            ));
      }
    }

    void stubLastFm({
      Map<String, List<LastFmTrack>> byArtist = const {},
      Map<String, List<LastFmTrack>> byTag = const {},
    }) {
      when(() => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((invocation) async =>
              byArtist[invocation.positionalArguments.first] ?? const []);
      when(() => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((invocation) async =>
              byTag[invocation.positionalArguments.first] ?? const []);
    }

    PlaylistDraft draftOf(Result<PlaylistDraft> result) =>
        (result as Ok<PlaylistDraft>).value;

    setUp(() async {
      // Muse (setUp above) has "Starlight". Genres:
      // - alternative: Radiohead (2 tracks), Muse (1), Placebo (1) → 4 tracks
      // - rock: Muse (1) and Guest, only featured on Placebo's track → 2
      await addArtist('muse', 'Muse', ['alternative', 'rock']);
      await addArtist('rh', 'Radiohead', ['alternative']);
      await addArtist('pl', 'Placebo', ['alternative']);
      await addArtist('gu', 'Guest', ['rock']);
      await addTrack('rh1', 'Airbag', ['rh']);
      await addTrack('rh2', 'No Surprises', ['rh']);
      await addTrack('pl1', 'Every You', ['pl', 'gu']);
    });

    test('asks for the top genres and their main artists', () async {
      stubLastFm();

      await repo.newFromYourGenres();

      // alternative: Radiohead (2), then Muse/Placebo tie → Muse by name.
      // rock: only Muse is a main artist; Muse is asked once.
      expect(
        verify(() => lastFm.getArtistTopTracks(
              captureAny(),
              limit: DiscoverRepository.tracksPerArtist,
            )).captured,
        ['Radiohead', 'Muse'],
      );
      expect(
        verify(() => lastFm.getTagTopTracks(
              captureAny(),
              limit: DiscoverRepository.tracksPerTag,
            )).captured,
        ['alternative', 'rock'],
      );
    });

    test('first your artists (half), then any artist of the genres',
        () async {
      stubLastFm(
        byArtist: {
          'Radiohead': [
            lf('Creep', 'Radiohead'),
            lf('Karma Police', 'Radiohead'),
          ],
          'Muse': [lf('Starlight'), lf('Uprising')], // Starlight is owned
        },
        byTag: {
          'alternative': [lf('Uprising'), lf('Song A', 'Band A')],
          'rock': [lf('Song B', 'Band B'), lf('Airbag', 'Radiohead')],
        },
      );
      spotify[q('Creep', 'Radiohead')] = [
        dto('creep', 'Creep', artists: ['Radiohead']),
      ];
      spotify[q('Karma Police', 'Radiohead')] = [
        dto('karma', 'Karma Police', artists: ['Radiohead']),
      ];
      spotify[q('Uprising')] = [dto('upr', 'Uprising')];
      spotify[q('Song A', 'Band A')] = [
        dto('a', 'Song A', artists: ['Band A']),
      ];
      spotify[q('Song B', 'Band B')] = [
        dto('b', 'Song B', artists: ['Band B']),
      ];

      final draft = draftOf(await repo.newFromYourGenres(maxTracks: 4));

      expect(draft.name, 'New music from your genres');
      // Part 1 (2 of 4): Creep, Uprising. Part 2: Uprising is already in
      // part 1 and Airbag is owned, so Song B, Song A.
      expect(draft.tracks.map((t) => t.id), ['creep', 'upr', 'b', 'a']);
    });

    test('part 2 fills the list when part 1 finds less', () async {
      stubLastFm(byTag: {
        'alternative': [
          lf('A1', 'Band'),
          lf('A2', 'Band'),
          lf('A3', 'Band'),
        ],
      });
      for (final name in ['A1', 'A2', 'A3']) {
        spotify[q(name, 'Band')] = [
          dto(name.toLowerCase(), name, artists: ['Band']),
        ];
      }

      final draft = draftOf(await repo.newFromYourGenres(maxTracks: 4));

      expect(draft.tracks.map((t) => t.id), ['a1', 'a2', 'a3']);
    });

    test('no genres yet returns an empty draft without calls', () async {
      await db.delete(db.artistGenres).go();
      stubLastFm();

      expect(draftOf(await repo.newFromYourGenres()).tracks, isEmpty);
      verifyNever(
        () => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')),
      );
      verifyNever(
        () => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')),
      );
    });

    test('a Last.fm error returns Error', () async {
      stubLastFm();
      when(() => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')))
          .thenThrow(const LastFmApiException(500, 'down'));

      expect(await repo.newFromYourGenres(), isA<Error<PlaylistDraft>>());
    });

    test('without Last.fm returns Error', () async {
      final noLastFm = DiscoverRepository(api: api, db: db, lastFm: null);

      expect(
        await noLastFm.newFromYourGenres(),
        isA<Error<PlaylistDraft>>(),
      );
    });
  });

  test('rankNewArtists sums matches and skips known artists', () {
    final ranked = DiscoverRepository.rankNewArtists(
      [
        [
          (name: 'Radiohead', match: 1.0),
          (name: 'Placebo', match: 0.8),
          (name: 'Coldplay', match: 0.5),
        ],
        [
          (name: 'coldplay', match: 0.6), // same artist, other case
          (name: 'Keane', match: 0.8),
        ],
      ],
      known: {DiscoverRepository.normalize('Radiohead')},
    );

    // Coldplay 1.1; Placebo and Keane tie at 0.8 → order of appearance.
    expect(ranked, ['Coldplay', 'Placebo', 'Keane']);
  });

  group('musicYouCouldLike', () {
    void stubLastFm({
      Map<String, List<LastFmTrack>> similarTracks = const {},
      Map<String, List<LastFmSimilarArtist>> similarArtists = const {},
      Map<String, List<String>> similarTags = const {},
      Map<String, List<LastFmTrack>> artistTop = const {},
      Map<String, List<LastFmTrack>> tagTop = const {},
    }) {
      when(() => lastFm.getSimilarTracks(
            any(),
            any(),
            limit: any(named: 'limit'),
          )).thenAnswer((i) async {
        final key = '${i.positionalArguments[0]}|${i.positionalArguments[1]}';
        return similarTracks[key] ?? const [];
      });
      when(() => lastFm.getSimilarArtists(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => similarArtists[i.positionalArguments.first] ?? const [],
      );
      when(() => lastFm.getSimilarTags(any())).thenAnswer(
        (i) async => similarTags[i.positionalArguments.first] ?? const [],
      );
      when(() => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => artistTop[i.positionalArguments.first] ?? const [],
      );
      when(() => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => tagTop[i.positionalArguments.first] ?? const [],
      );
    }

    PlaylistDraft draftOf(Result<PlaylistDraft> result) =>
        (result as Ok<PlaylistDraft>).value;

    setUp(() async {
      // Library: "Starlight" by Muse (setUp above, position 0, level 3)
      // and "Airbag" by Radiohead (position 1, level 5). Both artists
      // are "alternative".
      await db.into(db.artists).insert(
            ArtistsCompanion.insert(id: 'rh', name: 'Radiohead'),
          );
      await db.into(db.tracks).insert(TracksCompanion.insert(
            id: 'rh1',
            uri: 'spotify:track:rh1',
            name: 'Airbag',
            albumId: 'al',
            albumName: 'OK Computer',
            durationMs: 280000,
            position: 1,
          ));
      await db.into(db.trackArtists).insert(TrackArtistsCompanion.insert(
            trackId: 'rh1',
            artistId: 'rh',
            position: 0,
          ));
      for (final (id, level) in [('own', 3), ('rh1', 5)]) {
        await db.into(db.trackLevels).insert(
              TrackLevelsCompanion.insert(trackId: id, level: Value(level)),
            );
      }
      for (final artistId in ['muse', 'rh']) {
        await db.into(db.artistGenres).insert(ArtistGenresCompanion.insert(
              artistId: artistId,
              genre: 'alternative',
              source: GenreSource.lastFm,
            ));
      }
    });

    test('uses favourite tracks, top artists and top genres as seeds',
        () async {
      stubLastFm();

      await repo.musicYouCouldLike();

      // Highest level first: Airbag (5) before Starlight (3).
      expect(
        verify(() => lastFm.getSimilarTracks(
              captureAny(),
              captureAny(),
              limit: DiscoverRepository.similarTracksPerSeed,
            )).captured,
        ['Radiohead', 'Airbag', 'Muse', 'Starlight'],
      );
      expect(
        verify(() => lastFm.getSimilarArtists(
              captureAny(),
              limit: DiscoverRepository.similarArtistsPerSeed,
            )).captured,
        ['Muse', 'Radiohead'],
      );
      expect(
        verify(() => lastFm.getSimilarTags(captureAny())).captured,
        ['alternative'],
      );
    });

    test('another shuffle uses other seeds', () async {
      final shuffled = DiscoverRepository(
        api: api,
        db: db,
        lastFm: lastFm,
        shuffle: reverseOrder,
      );
      stubLastFm();

      await shuffled.musicYouCouldLike();

      // Pool order reversed: Starlight before Airbag, Radiohead before Muse.
      expect(
        verify(() => lastFm.getSimilarTracks(
              captureAny(),
              captureAny(),
              limit: any(named: 'limit'),
            )).captured,
        ['Muse', 'Starlight', 'Radiohead', 'Airbag'],
      );
      expect(
        verify(() => lastFm.getSimilarArtists(
              captureAny(),
              limit: any(named: 'limit'),
            )).captured,
        ['Radiohead', 'Muse'],
      );
    });

    test('mixes similar tracks, new artists and similar genres', () async {
      stubLastFm(
        similarTracks: {
          'Radiohead|Airbag': [
            lf('Creep', 'Radiohead'),
            lf('Starlight'), // owned
          ],
          'Muse|Starlight': [lf('Supermassive')],
        },
        similarArtists: {
          'Muse': [
            (name: 'Radiohead', match: 1.0), // in the library
            (name: 'Placebo', match: 0.8),
            (name: 'Coldplay', match: 0.5),
          ],
          'Radiohead': [
            (name: 'Coldplay', match: 0.6),
            (name: 'Muse', match: 0.9), // in the library
          ],
        },
        similarTags: {
          'alternative': ['Indie', 'Alternative'], // the seed is skipped
        },
        artistTop: {
          'Coldplay': [lf('Yellow', 'Coldplay')],
          'Placebo': [lf('Every You', 'Placebo')],
        },
        tagTop: {
          'indie': [lf('Song I', 'Band I')],
        },
      );
      for (final (id, name, artist) in [
        ('creep', 'Creep', 'Radiohead'),
        ('super', 'Supermassive', 'Muse'),
        ('yellow', 'Yellow', 'Coldplay'),
        ('every', 'Every You', 'Placebo'),
        ('songi', 'Song I', 'Band I'),
      ]) {
        spotify[q(name, artist)] = [dto(id, name, artists: [artist])];
      }

      final draft = draftOf(await repo.musicYouCouldLike());

      expect(draft.name, 'Music you could like');
      expect(
        draft.tracks.map((t) => t.id),
        ['creep', 'yellow', 'songi', 'super', 'every'],
      );
      // New artists by total match: Coldplay (1.1), Placebo (0.8).
      expect(
        verify(() => lastFm.getArtistTopTracks(
              captureAny(),
              limit: DiscoverRepository.tracksPerNewArtist,
            )).captured,
        ['Coldplay', 'Placebo'],
      );
      expect(
        verify(() => lastFm.getTagTopTracks(
              captureAny(),
              limit: DiscoverRepository.tracksPerNewGenre,
            )).captured,
        ['indie'],
      );
    });

    test('an empty library returns an empty draft without calls', () async {
      await db.delete(db.trackArtists).go();
      await db.delete(db.artistGenres).go();
      await db.delete(db.tracks).go();
      stubLastFm();

      expect(draftOf(await repo.musicYouCouldLike()).tracks, isEmpty);
      verifyZeroInteractions(lastFm);
    });

    test('a Last.fm error returns Error', () async {
      stubLastFm();
      when(() => lastFm.getSimilarArtists(any(), limit: any(named: 'limit')))
          .thenThrow(const LastFmApiException(500, 'down'));

      expect(await repo.musicYouCouldLike(), isA<Error<PlaylistDraft>>());
    });

    test('without Last.fm returns Error', () async {
      final noLastFm = DiscoverRepository(api: api, db: db, lastFm: null);

      expect(
        await noLastFm.musicYouCouldLike(),
        isA<Error<PlaylistDraft>>(),
      );
    });
  });

  group('musicToTry', () {
    void stubLastFm({
      List<LastFmTrack> chartTracks = const [],
      List<String> chartArtists = const [],
      List<String> chartTags = const [],
      Map<String, List<LastFmTrack>> artistTop = const {},
      Map<String, List<LastFmTrack>> tagTop = const {},
    }) {
      when(() => lastFm.getChartTopTracks(limit: any(named: 'limit')))
          .thenAnswer((_) async => chartTracks);
      when(() => lastFm.getChartTopArtists(limit: any(named: 'limit')))
          .thenAnswer((_) async => chartArtists);
      when(() => lastFm.getChartTopTags(limit: any(named: 'limit')))
          .thenAnswer((_) async => chartTags);
      when(() => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => artistTop[i.positionalArguments.first] ?? const [],
      );
      when(() => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => tagTop[i.positionalArguments.first] ?? const [],
      );
    }

    PlaylistDraft draftOf(Result<PlaylistDraft> result) =>
        (result as Ok<PlaylistDraft>).value;

    setUp(() async {
      // Library: Muse ("Starlight", setUp above) with genres rock, hip-hop.
      for (final genre in ['rock', 'hip-hop']) {
        await db.into(db.artistGenres).insert(ArtistGenresCompanion.insert(
              artistId: 'muse',
              genre: genre,
              source: GenreSource.lastFm,
            ));
      }
    });

    test('mixes chart tracks, new artists and new genres', () async {
      stubLastFm(
        chartTracks: [
          lf('Uprising'), // artist in the library
          lf('Starlight'), // owned
          lf('Hit 1', 'Star A'),
          lf('Hit 2', 'Star B'),
        ],
        chartArtists: ['Muse', 'Star C', 'Star D'],
        chartTags: ['seen live', 'Hip Hop', 'Rock', 'K-Pop', 'jazz'],
        artistTop: {
          'Star C': [lf('C1', 'Star C')],
          'Star D': [lf('D1', 'Star D')],
        },
        tagTop: {
          'k-pop': [lf('K1', 'Band K')],
          'jazz': [
            lf('J1', 'Band J'),
            lf('Supermassive'), // by Muse, in the library
          ],
        },
      );
      for (final (id, name, artist) in [
        ('h1', 'Hit 1', 'Star A'),
        ('h2', 'Hit 2', 'Star B'),
        ('c1', 'C1', 'Star C'),
        ('d1', 'D1', 'Star D'),
        ('k1', 'K1', 'Band K'),
        ('j1', 'J1', 'Band J'),
      ]) {
        spotify[q(name, artist)] = [dto(id, name, artists: [artist])];
      }

      final draft = draftOf(await repo.musicToTry());

      expect(draft.name, 'Music to try');
      expect(
        draft.tracks.map((t) => t.id),
        ['h1', 'c1', 'k1', 'h2', 'd1', 'j1'],
      );
      // Artists not in the library travel with the draft (preview names).
      expect(draft.artistNames, containsPair('ar-h1-0', 'Star A'));
      expect(draft.artistNames, containsPair('ar-j1-0', 'Band J'));
    });

    test('skips your artists and genres (and non-genre tags)', () async {
      stubLastFm(
        chartArtists: ['MUSE', 'Star C'],
        // "Hip Hop" = your "hip-hop"; "seen live" is not a genre.
        chartTags: ['seen live', 'Hip Hop', 'rock', 'jazz'],
      );

      await repo.musicToTry();

      expect(
        verify(() => lastFm.getArtistTopTracks(
              captureAny(),
              limit: DiscoverRepository.tracksPerChartArtist,
            )).captured,
        ['Star C'],
      );
      expect(
        verify(() => lastFm.getTagTopTracks(
              captureAny(),
              limit: DiscoverRepository.tracksPerNewGenre,
            )).captured,
        ['jazz'],
      );
    });

    test('reads each chart once and limits artists and genres', () async {
      stubLastFm(
        chartArtists: [for (var i = 0; i < 8; i++) 'Artist $i'],
        chartTags: [for (var i = 0; i < 6; i++) 'genre $i'],
      );

      await repo.musicToTry();

      verify(() => lastFm.getChartTopTracks(
            limit: DiscoverRepository.chartSize,
          )).called(1);
      verify(() => lastFm.getChartTopArtists(
            limit: DiscoverRepository.chartSize,
          )).called(1);
      verify(() => lastFm.getChartTopTags(
            limit: DiscoverRepository.chartSize,
          )).called(1);
      verify(() => lastFm.getArtistTopTracks(
            any(),
            limit: any(named: 'limit'),
          )).called(DiscoverRepository.chartArtistsPerRun);
      verify(() => lastFm.getTagTopTracks(
            any(),
            limit: any(named: 'limit'),
          )).called(DiscoverRepository.chartGenresPerRun);
    });

    test('picks chart artists and genres at random among the new ones',
        () async {
      final shuffled = DiscoverRepository(
        api: api,
        db: db,
        lastFm: lastFm,
        shuffle: reverseOrder,
      );
      stubLastFm(
        chartArtists: ['Muse', for (var i = 0; i < 8; i++) 'Artist $i'],
        chartTags: ['rock', for (var i = 0; i < 6; i++) 'genre $i'],
      );

      await shuffled.musicToTry();

      // Not always the first ones of the chart; never your Muse or rock.
      expect(
        verify(() => lastFm.getArtistTopTracks(
              captureAny(),
              limit: any(named: 'limit'),
            )).captured,
        ['Artist 7', 'Artist 6', 'Artist 5', 'Artist 4', 'Artist 3'],
      );
      expect(
        verify(() => lastFm.getTagTopTracks(
              captureAny(),
              limit: any(named: 'limit'),
            )).captured,
        ['genre 5', 'genre 4', 'genre 3'],
      );
    });

    test('a Last.fm error returns Error', () async {
      stubLastFm();
      when(() => lastFm.getChartTopTags(limit: any(named: 'limit')))
          .thenThrow(const LastFmApiException(500, 'down'));

      expect(await repo.musicToTry(), isA<Error<PlaylistDraft>>());
    });

    test('without Last.fm returns Error', () async {
      final noLastFm = DiscoverRepository(api: api, db: db, lastFm: null);

      expect(await noLastFm.musicToTry(), isA<Error<PlaylistDraft>>());
    });
  });

  group('fromOwnParameters', () {
    void stubLastFm({
      Map<String, List<LastFmTrack>> artistTop = const {},
      Map<String, List<LastFmTrack>> tagTop = const {},
    }) {
      when(() => lastFm.getArtistTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => artistTop[i.positionalArguments.first] ?? const [],
      );
      when(() => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')))
          .thenAnswer(
        (i) async => tagTop[i.positionalArguments.first] ?? const [],
      );
    }

    PlaylistDraft draftOf(Result<PlaylistDraft> result) =>
        (result as Ok<PlaylistDraft>).value;

    setUp(() async {
      // Muse ("Starlight", setUp above) is "rock".
      await db.into(db.artistGenres).insert(ArtistGenresCompanion.insert(
            artistId: 'muse',
            genre: 'rock',
            source: GenreSource.lastFm,
          ));
      spotify[q('Every You', 'Placebo')] = [
        dto('every', 'Every You', artists: ['Placebo']),
      ];
      spotify[q('Song R', 'Band R')] = [
        dto('songr', 'Song R', artists: ['Band R']),
      ];
    });

    test('no parameters returns an empty draft without calls', () async {
      final draft = draftOf(await repo.fromOwnParameters());

      expect(draft.tracks, isEmpty);
      verifyZeroInteractions(lastFm);
    });

    test('artists only: mode 1 with the chosen artists', () async {
      stubLastFm(artistTop: {
        'Placebo': [lf('Every You', 'Placebo')],
      });

      final draft = draftOf(await repo.fromOwnParameters(
        artists: ['Placebo'],
      ));

      expect(draft.name, 'Own parameters');
      expect(draft.tracks.map((t) => t.id), ['every']);
      // Not the top artist of the library (Muse).
      expect(
        verify(() => lastFm.getArtistTopTracks(
              captureAny(),
              limit: any(named: 'limit'),
            )).captured,
        ['Placebo'],
      );
    });

    test('genres only: mode 2 with the chosen genres', () async {
      stubLastFm(tagTop: {
        'rock': [lf('Song R', 'Band R')],
      });

      final draft = draftOf(await repo.fromOwnParameters(genres: ['rock']));

      expect(draft.name, 'Own parameters');
      expect(draft.tracks.map((t) => t.id), ['songr']);
      expect(
        verify(() => lastFm.getTagTopTracks(
              captureAny(),
              limit: any(named: 'limit'),
            )).captured,
        ['rock'],
      );
    });

    test('both: mixes the two lists without repeats', () async {
      stubLastFm(
        artistTop: {
          'Placebo': [lf('Every You', 'Placebo')],
        },
        tagTop: {
          'rock': [
            lf('Song R', 'Band R'),
            lf('Every You', 'Placebo'), // already from the artist part
          ],
        },
      );

      final draft = draftOf(await repo.fromOwnParameters(
        artists: ['Placebo'],
        genres: ['rock'],
      ));

      expect(draft.tracks.map((t) => t.id), ['every', 'songr']);
      expect(draft.artistNames, {
        'ar-every-0': 'Placebo',
        'ar-songr-0': 'Band R',
      });
    });

    test('an error in one part returns Error', () async {
      stubLastFm();
      when(() => lastFm.getTagTopTracks(any(), limit: any(named: 'limit')))
          .thenThrow(const LastFmApiException(500, 'down'));

      expect(
        await repo.fromOwnParameters(artists: ['Placebo'], genres: ['rock']),
        isA<Error<PlaylistDraft>>(),
      );
    });
  });

  test('artistNamesOf maps every artist id of the results', () {
    final results = [
      SearchResult(
        track: const Track(
          id: 't1',
          uri: 'spotify:track:t1',
          name: 'Song',
          artistIds: ['a1', 'a2'],
          albumId: 'al',
          albumName: 'Album',
          duration: Duration(minutes: 3),
        ),
        artistNames: const ['Muse', 'Guest'],
        inMain: false,
      ),
      SearchResult(
        track: const Track(
          id: 't2',
          uri: 'spotify:track:t2',
          name: 'Other',
          artistIds: ['a3', 'a4'],
          albumId: 'al',
          albumName: 'Album',
          duration: Duration(minutes: 3),
        ),
        artistNames: const ['Solo'], // fewer names than ids
        inMain: false,
      ),
    ];

    expect(DiscoverRepository.artistNamesOf(results), {
      'a1': 'Muse',
      'a2': 'Guest',
      'a3': 'Solo',
    });
  });
}