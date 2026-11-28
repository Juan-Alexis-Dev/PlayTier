import '../../domain/engines/genre_cleaner.dart';
import '../../domain/models/discover_mode.dart';
import '../../domain/models/playlist_draft.dart';
import '../../domain/models/result.dart';
import '../../domain/models/search_result.dart';
import '../../domain/models/track.dart';
import '../services/lastfm/lastfm_service.dart';
import '../services/local/app_database.dart';
import '../services/spotify/dto/spotify_playlist_item_dto.dart';
import '../services/spotify/spotify_api_service.dart';

/// Discover (FR-10): turns Last.fm suggestions into Spotify tracks the user
/// does not have yet.
///
/// Each discover mode builds a list of Last.fm candidates and passes it to
/// [matchTracks], which:
/// 1. drops candidates already in the main playlist (same name + artist),
///    without calling Spotify;
/// 2. searches each remaining one on Spotify and keeps the first result
///    with the same name and artist (FR-10.6);
/// 3. drops tracks whose Spotify id is in the main playlist, and
///    duplicates (same id, or same song from another album).
class DiscoverRepository {
  DiscoverRepository({
    required this._api,
    required this._db,
    required this._lastFm,
  });

  final SpotifyApiService _api;
  final AppDatabase _db;

  /// Null when no Last.fm API key is configured.
  final LastFmService? _lastFm;

  /// Default size of a discover playlist.
  static const defaultMaxTracks = 50;

  /// Spotify results checked per candidate.
  static const _resultsPerSearch = 5;

  /// Spotify searches sent at the same time.
  static const _parallelSearches = 5;

  /// Mode 1: user's artists with the most tracks in the main playlist.
  static const artistsPerRun = 10;

  /// Mode 1: Last.fm top tracks requested per artist. Most popular ones
  /// are often owned already, so this is larger than what is kept.
  static const tracksPerArtist = 15;

  /// Mode 2: genres with the most tracks in the main playlist.
  static const genresPerRun = 5;

  /// Mode 2: user's artists of each genre whose top tracks are used.
  static const artistsPerGenre = 2;

  /// Mode 2: Last.fm top tracks requested per genre (any artist).
  static const tracksPerTag = 30;

  /// Mode 3: favourite tracks (highest level) used as seeds.
  static const seedTracksPerRun = 5;

  /// Mode 3: Last.fm similar tracks requested per seed track.
  static const similarTracksPerSeed = 20;

  /// Mode 3: user's top artists used as seeds.
  static const seedArtistsPerRun = 5;

  /// Mode 3: Last.fm similar artists requested per seed artist.
  static const similarArtistsPerSeed = 10;

  /// Mode 3: new artists (not in the library) whose top tracks are used.
  static const newArtistsPerRun = 5;

  /// Mode 3: top tracks requested per new artist.
  static const tracksPerNewArtist = 5;

  /// Mode 3: user's top genres used as seeds.
  static const seedGenresPerRun = 3;

  /// Mode 3: similar genres (not the seeds) whose top tracks are used.
  static const newGenresPerRun = 3;

  /// Mode 3: top tracks requested per similar genre.
  static const tracksPerNewGenre = 15;

  /// Mode 4: size of each Last.fm global chart that is read.
  static const chartSize = 50;

  /// Mode 4: chart artists (not in the library) whose top tracks are used.
  static const chartArtistsPerRun = 5;

  /// Mode 4: top tracks requested per chart artist.
  static const tracksPerChartArtist = 3;

  /// Mode 4: chart genres (not in the library) whose top tracks are used.
  static const chartGenresPerRun = 3;

  /// Discover needs Last.fm; the UI hides it when this is false.
  bool get isAvailable => _lastFm != null;

  /// Mode 1, "New music from your artists" (FR-10.1).
  ///
  /// Takes the [artistsPerRun] main artists with the most tracks in the
  /// main playlist, asks Last.fm for each one's top tracks, drops the ones
  /// already owned and mixes the rest one artist at a time (most popular
  /// first), so no artist fills the whole list.
  ///
  /// With [artists] (own parameters, FR-10.5) those names are used
  /// instead of the top artists.
  Future<Result<PlaylistDraft>> newFromYourArtists({
    List<String>? artists,
    int maxTracks = defaultMaxTracks,
  }) async {
    final lastFm = _lastFm;
    if (lastFm == null) return Result.error(_noLastFm);

    try {
      artists ??= await _topArtistNames(artistsPerRun);
      final topTracks = await Future.wait([
        for (final artist in artists)
          lastFm.getArtistTopTracks(artist, limit: tracksPerArtist),
      ]);
      // Drop owned tracks before mixing, so every artist keeps its turn.
      final owned = (await _ownedSongs()).keys;
      final fresh = [for (final list in topTracks) _fresh(list, owned)];
      return _draft(
        DiscoverMode.fromArtists,
        await matchTracks(interleave(fresh), maxTracks: maxTracks),
      );
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Mode 2, "New music from your genres" (FR-10.2).
  ///
  /// Takes the [genresPerRun] genres with the most tracks in the main
  /// playlist and builds the list in two parts, about half each:
  /// 1. top tracks (Last.fm) of the user's own [artistsPerGenre] artists
  ///    of each genre that the user does not have;
  /// 2. then the genre's most popular tracks from any artist
  ///    (`tag.getTopTracks`).
  ///
  /// Each part mixes genres one at a time. If part 1 finds fewer tracks,
  /// part 2 fills the rest.
  ///
  /// With [genres] (own parameters, FR-10.5, lower-case as stored) those
  /// are used instead of the top genres.
  Future<Result<PlaylistDraft>> newFromYourGenres({
    List<String>? genres,
    int maxTracks = defaultMaxTracks,
  }) async {
    final lastFm = _lastFm;
    if (lastFm == null) return Result.error(_noLastFm);

    try {
      genres ??= await _topGenres(genresPerRun);
      final artistsByGenre = await _topArtistsOfGenres(
        genres,
        perGenre: artistsPerGenre,
      );
      // An artist in several genres is asked for only once.
      final artists = {
        for (final genre in genres) ...?artistsByGenre[genre],
      }.toList();

      final responses = await Future.wait([
        for (final artist in artists)
          lastFm.getArtistTopTracks(artist, limit: tracksPerArtist),
        for (final genre in genres)
          lastFm.getTagTopTracks(genre, limit: tracksPerTag),
      ]);
      final byArtist = {
        for (final (i, artist) in artists.indexed) artist: responses[i],
      };
      final byTag = responses.sublist(artists.length);

      final owned = (await _ownedSongs()).keys;
      final fromYourArtists = interleave([
        for (final genre in genres)
          interleave([
            for (final artist in artistsByGenre[genre] ?? const <String>[])
              _fresh(byArtist[artist]!, owned),
          ]),
      ]);
      final fromAnyArtist = interleave([
        for (final list in byTag) _fresh(list, owned),
      ]);

      // Part 1, up to half of the list.
      final first = await matchTracks(
        fromYourArtists,
        maxTracks: maxTracks ~/ 2,
      );
      if (first case Error(:final error)) return Result.error(error);
      final firstTracks = (first as Ok<List<SearchResult>>).value;

      // Part 2 fills the rest, without repeating part 1.
      final firstIds = {for (final r in firstTracks) r.track.id};
      final firstKeys = {
        for (final r in firstTracks) songKey(r.track.name, r.artistNames.first),
      };
      final second = await matchTracks(
        [
          for (final c in fromAnyArtist)
            if (!firstKeys.contains(songKey(c.name, c.artist))) c,
        ],
        maxTracks: maxTracks - firstTracks.length,
      );
      return _draft(DiscoverMode.fromGenres, switch (second) {
        Ok(:final value) => Result.ok([
            ...firstTracks,
            for (final r in value)
              if (!firstIds.contains(r.track.id)) r,
          ]),
        Error(:final error) => Result.error(error),
      });
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Own parameters (FR-10.5): mode 1 with [artists] and/or mode 2 with
  /// [genres].
  ///
  /// With both, each mode gets about half of [maxTracks] and the two
  /// lists are mixed one track at a time, without repeats. The draft is
  /// named "Own parameters"; the view model renames it after the chips.
  Future<Result<PlaylistDraft>> fromOwnParameters({
    List<String> artists = const [],
    List<String> genres = const [],
    int maxTracks = defaultMaxTracks,
  }) async {
    if (artists.isEmpty && genres.isEmpty) {
      return Result.ok(
        PlaylistDraft(name: DiscoverMode.custom.title, tracks: const []),
      );
    }
    if (genres.isEmpty) {
      return _renamed(
        await newFromYourArtists(artists: artists, maxTracks: maxTracks),
      );
    }
    if (artists.isEmpty) {
      return _renamed(
        await newFromYourGenres(genres: genres, maxTracks: maxTracks),
      );
    }

    final byArtists = await newFromYourArtists(
      artists: artists,
      maxTracks: maxTracks ~/ 2,
    );
    if (byArtists case Error(:final error)) return Result.error(error);
    final artistDraft = (byArtists as Ok<PlaylistDraft>).value;
    final artistTracks = artistDraft.tracks;

    final byGenres = await newFromYourGenres(
      genres: genres,
      maxTracks: maxTracks - artistTracks.length,
    );
    if (byGenres case Error(:final error)) return Result.error(error);
    final genreDraft = (byGenres as Ok<PlaylistDraft>).value;
    final artistIds = {for (final t in artistTracks) t.id};
    final genreTracks = [
      for (final t in genreDraft.tracks)
        if (!artistIds.contains(t.id)) t,
    ];

    return Result.ok(PlaylistDraft(
      name: DiscoverMode.custom.title,
      tracks: interleave([artistTracks, genreTracks]),
      artistNames: {...artistDraft.artistNames, ...genreDraft.artistNames},
    ));
  }

  static Result<PlaylistDraft> _renamed(Result<PlaylistDraft> result) =>
      switch (result) {
        Ok(:final value) =>
          Result.ok(value.copyWith(name: DiscoverMode.custom.title)),
        Error() => result,
      };

  /// Mode 3, "Music you could like" (FR-10.3): inside your taste.
  ///
  /// Mixes three sources, one track of each per turn:
  /// 1. tracks similar to your favourites (highest level, then most
  ///    recently added) — `track.getSimilar`;
  /// 2. top tracks of artists similar to your top artists that are not in
  ///    your library, best match first — `artist.getSimilar`;
  /// 3. top tracks of genres similar to your top genres (not the genres
  ///    themselves) — `tag.getSimilar`, often empty.
  Future<Result<PlaylistDraft>> musicYouCouldLike({
    int maxTracks = defaultMaxTracks,
  }) async {
    final lastFm = _lastFm;
    if (lastFm == null) return Result.error(_noLastFm);

    try {
      final seedTracks = await _seedTracks(seedTracksPerRun);
      final seedArtists = await _topArtistNames(seedArtistsPerRun);
      final seedGenres = await _topGenres(seedGenresPerRun);

      // Round 1: what is similar to the seeds.
      final similarTracks = await Future.wait([
        for (final seed in seedTracks)
          lastFm.getSimilarTracks(
            seed.artist,
            seed.name,
            limit: similarTracksPerSeed,
          ),
      ]);
      final similarArtists = await Future.wait([
        for (final artist in seedArtists)
          lastFm.getSimilarArtists(artist, limit: similarArtistsPerSeed),
      ]);
      final similarTags = await Future.wait([
        for (final genre in seedGenres) lastFm.getSimilarTags(genre),
      ]);

      final newArtists = rankNewArtists(
        similarArtists,
        known: await _libraryArtistNames(),
      ).take(newArtistsPerRun).toList();
      final newGenres = _newGenres(similarTags, seeds: seedGenres)
          .take(newGenresPerRun)
          .toList();

      // Round 2: top tracks of the new artists and genres.
      final artistTracks = await Future.wait([
        for (final artist in newArtists)
          lastFm.getArtistTopTracks(artist, limit: tracksPerNewArtist),
      ]);
      final genreTracks = await Future.wait([
        for (final genre in newGenres)
          lastFm.getTagTopTracks(genre, limit: tracksPerNewGenre),
      ]);

      final owned = (await _ownedSongs()).keys;
      List<LastFmTrack> mixed(List<List<LastFmTrack>> lists) =>
          interleave([for (final list in lists) _fresh(list, owned)]);

      return _draft(
        DiscoverMode.youCouldLike,
        await matchTracks(
          interleave([
            mixed(similarTracks),
            mixed(artistTracks),
            mixed(genreTracks),
          ]),
          maxTracks: maxTracks,
        ),
      );
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Mode 4, "Music to try" (FR-10.4): outside your taste.
  ///
  /// Uses Last.fm's global charts and keeps only what is different from
  /// the library: no artist you have, no genre you have. Mixes three
  /// sources, one track of each per turn:
  /// 1. chart top tracks;
  /// 2. top tracks of the first [chartArtistsPerRun] chart artists;
  /// 3. top tracks of the first [chartGenresPerRun] chart genres (tags
  ///    that are not genres, like "seen live", are skipped).
  Future<Result<PlaylistDraft>> musicToTry({
    int maxTracks = defaultMaxTracks,
  }) async {
    final lastFm = _lastFm;
    if (lastFm == null) return Result.error(_noLastFm);

    try {
      final knownArtists = await _libraryArtistNames();
      final knownGenres = await _libraryGenres();

      final chartTracks = await lastFm.getChartTopTracks(limit: chartSize);
      final chartArtists = await lastFm.getChartTopArtists(limit: chartSize);
      final chartTags = await lastFm.getChartTopTags(limit: chartSize);

      final newArtists = [
        for (final artist in chartArtists)
          if (!knownArtists.contains(normalize(artist))) artist,
      ].take(chartArtistsPerRun).toList();
      final newGenres = [
        for (final genre in GenreCleaner.clean(
          [for (final tag in chartTags) (name: tag, count: 0)],
          artistName: '',
          limit: null,
        ))
          if (!knownGenres.contains(normalize(genre))) genre,
      ].take(chartGenresPerRun).toList();

      final artistTracks = await Future.wait([
        for (final artist in newArtists)
          lastFm.getArtistTopTracks(artist, limit: tracksPerChartArtist),
      ]);
      final genreTracks = await Future.wait([
        for (final genre in newGenres)
          lastFm.getTagTopTracks(genre, limit: tracksPerNewGenre),
      ]);

      // Not owned and not by an artist of the library.
      final owned = (await _ownedSongs()).keys;
      List<LastFmTrack> outside(List<LastFmTrack> tracks) => [
            for (final t in _fresh(tracks, owned))
              if (!knownArtists.contains(normalize(t.artist))) t,
          ];

      return _draft(
        DiscoverMode.toTry,
        await matchTracks(
          interleave([
            outside(chartTracks),
            interleave([for (final list in artistTracks) outside(list)]),
            interleave([for (final list in genreTracks) outside(list)]),
          ]),
          maxTracks: maxTracks,
        ),
      );
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Matches Last.fm [candidates] to Spotify tracks not in the main
  /// playlist, keeping the candidates' order, up to [maxTracks].
  ///
  /// Results have `inMain: false`. Candidates with no Spotify match are
  /// skipped. Any Spotify error returns [Error].
  Future<Result<List<SearchResult>>> matchTracks(
    List<LastFmTrack> candidates, {
    int maxTracks = defaultMaxTracks,
  }) async {
    try {
      final owned = await _ownedSongs();

      // Skip owned and repeated candidates before searching.
      final candidateKeys = <String>{};
      final pending = [
        for (final c in candidates)
          if (!owned.keys.contains(songKey(c.name, c.artist)) &&
              candidateKeys.add(songKey(c.name, c.artist)))
            c,
      ];

      final matches = <SearchResult>[];
      final matchIds = <String>{};
      final matchKeys = <String>{};
      for (var start = 0;
          start < pending.length && matches.length < maxTracks;
          start += _parallelSearches) {
        final batch = pending.skip(start).take(_parallelSearches);
        final found = await Future.wait(batch.map(_findOnSpotify));

        for (final item in found) {
          if (item == null || matches.length >= maxTracks) continue;
          if (owned.ids.contains(item.id) || !matchIds.add(item.id)) continue;
          // Same song under Spotify's name, or from another album
          // (single vs album version).
          final key = songKey(item.name, item.artists.first.name);
          if (owned.keys.contains(key) || !matchKeys.add(key)) continue;

          matches.add(SearchResult(
            track: _toTrack(item),
            artistNames: [for (final a in item.artists) a.name],
            inMain: false,
          ));
        }
      }
      return Result.ok(matches);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Wraps matched tracks in a draft named after [mode].
  static Result<PlaylistDraft> _draft(
    DiscoverMode mode,
    Result<List<SearchResult>> matched,
  ) {
    return switch (matched) {
      Ok(:final value) => Result.ok(PlaylistDraft(
          name: mode.title,
          tracks: [for (final r in value) r.track],
          artistNames: artistNamesOf(value),
        )),
      Error(:final error) => Result.error(error),
    };
  }

  /// Artist id → name of every matched track, so the preview can show
  /// artists that are not in the local database.
  static Map<String, String> artistNamesOf(List<SearchResult> results) => {
        for (final r in results)
          for (final (i, id) in r.track.artistIds.indexed)
            if (i < r.artistNames.length) id: r.artistNames[i],
      };

  /// Main artists (position 0) by number of tracks in the main playlist,
  /// most first; ties by name.
  Future<List<String>> _topArtistNames(int limit) async {
    final rows = await _db.customSelect(
      'SELECT a.name AS name, COUNT(*) AS c '
      'FROM track_artists ta '
      'JOIN artists a ON a.id = ta.artist_id '
      'WHERE ta.position = 0 '
      'GROUP BY a.id '
      'ORDER BY c DESC, a.name '
      'LIMIT $limit',
    ).get();
    return [for (final row in rows) row.read<String>('name')];
  }

  /// Genres by number of tracks in the main playlist, most first; ties by
  /// name. A track counts for a genre when any of its artists has it
  /// (same rule as the Genres tab).
  Future<List<String>> _topGenres(int limit) async {
    final rows = await _db.customSelect(
      'SELECT ag.genre AS genre, COUNT(DISTINCT ta.track_id) AS c '
      'FROM artist_genres ag '
      'JOIN track_artists ta ON ta.artist_id = ag.artist_id '
      'GROUP BY ag.genre '
      'ORDER BY c DESC, ag.genre '
      'LIMIT $limit',
    ).get();
    return [for (final row in rows) row.read<String>('genre')];
  }

  /// For each of [genres], its main artists (position 0) with the most
  /// tracks in the main playlist, up to [perGenre]; ties by name.
  Future<Map<String, List<String>>> _topArtistsOfGenres(
    List<String> genres, {
    required int perGenre,
  }) async {
    if (genres.isEmpty) return {};
    final rows = await _db.customSelect(
      'SELECT ag.genre AS genre, a.name AS name, COUNT(*) AS c '
      'FROM artist_genres ag '
      'JOIN artists a ON a.id = ag.artist_id '
      'JOIN track_artists ta ON ta.artist_id = a.id '
      'WHERE ta.position = 0 '
      'GROUP BY ag.genre, a.id '
      'ORDER BY c DESC, a.name',
    ).get();

    final wanted = genres.toSet();
    final result = <String, List<String>>{};
    for (final row in rows) {
      final genre = row.read<String>('genre');
      if (!wanted.contains(genre)) continue;
      final list = result.putIfAbsent(genre, () => []);
      if (list.length < perGenre) list.add(row.read<String>('name'));
    }
    return result;
  }

  /// Favourite tracks of the main playlist with their main artist: highest
  /// level first, then most recently added.
  Future<List<LastFmTrack>> _seedTracks(int limit) async {
    final rows = await _db.customSelect(
      'SELECT t.name AS name, a.name AS artist '
      'FROM tracks t '
      'JOIN track_artists ta ON ta.track_id = t.id AND ta.position = 0 '
      'JOIN artists a ON a.id = ta.artist_id '
      'LEFT JOIN track_levels l ON l.track_id = t.id '
      'ORDER BY COALESCE(l.level, 1) DESC, '
      't.added_at IS NULL, t.added_at DESC, t.position '
      'LIMIT $limit',
    ).get();
    return [
      for (final row in rows)
        (name: row.read<String>('name'), artist: row.read<String>('artist')),
    ];
  }

  /// Normalized names of every artist in the library.
  Future<Set<String>> _libraryArtistNames() async {
    final rows = await _db.select(_db.artists).get();
    return {for (final row in rows) normalize(row.name)};
  }

  /// Normalized genres of every artist in the library.
  Future<Set<String>> _libraryGenres() async {
    final rows = await _db.select(_db.artistGenres).get();
    return {for (final row in rows) normalize(row.genre)};
  }

  /// Similar artists from several seeds, best total match first, without
  /// the [known] (normalized) names. Ties keep the order of appearance.
  static List<String> rankNewArtists(
    List<List<LastFmSimilarArtist>> similar, {
    required Set<String> known,
  }) {
    final scores = <String, double>{};
    final names = <String, String>{};
    for (final list in similar) {
      for (final artist in list) {
        final key = normalize(artist.name);
        if (known.contains(key)) continue;
        names.putIfAbsent(key, () => artist.name);
        scores[key] = (scores[key] ?? 0) + artist.match;
      }
    }
    final keys = scores.keys.toList();
    // Stable sort: `keys` is in order of appearance.
    final order = {for (final (i, k) in keys.indexed) k: i};
    keys.sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      return byScore != 0 ? byScore : order[a]!.compareTo(order[b]!);
    });
    return [for (final key in keys) names[key]!];
  }

  /// Similar tags mixed one seed at a time, lower-cased, without repeats
  /// or the [seeds] themselves.
  static List<String> _newGenres(
    List<List<String>> similar, {
    required List<String> seeds,
  }) {
    final seen = {for (final s in seeds) s.toLowerCase()};
    return [
      for (final tag in interleave(similar))
        if (seen.add(tag.toLowerCase())) tag.toLowerCase(),
    ];
  }

  /// [tracks] without the songs whose key is in [owned].
  static List<LastFmTrack> _fresh(
    List<LastFmTrack> tracks,
    Set<String> owned,
  ) =>
      [
        for (final t in tracks)
          if (!owned.contains(songKey(t.name, t.artist))) t,
      ];

  /// Takes the 1st item of every list, then the 2nd, and so on.
  ///
  /// `[[a1, a2], [b1], [c1, c2, c3]]` → `[a1, b1, c1, a2, c2, c3]`.
  static List<T> interleave<T>(List<List<T>> lists) {
    final result = <T>[];
    final longest = lists.fold(0, (max, l) => l.length > max ? l.length : max);
    for (var i = 0; i < longest; i++) {
      for (final list in lists) {
        if (i < list.length) result.add(list[i]);
      }
    }
    return result;
  }

  static final _noLastFm = Exception('Last.fm API key is not configured.');

  /// First Spotify track with the candidate's name and artist, or null.
  Future<SpotifyPlaylistItemDto?> _findOnSpotify(LastFmTrack candidate) async {
    final name = _clean(candidate.name);
    final artist = _clean(candidate.artist);
    final items = await _api.searchTracks(
      'track:"$name" artist:"$artist"',
      limit: _resultsPerSearch,
    );

    final wantedName = normalize(candidate.name);
    final wantedArtist = normalize(candidate.artist);
    for (final item in items) {
      if (item.artists.isEmpty) continue;
      if (normalize(item.name) != wantedName) continue;
      if (item.artists.any((a) => normalize(a.name) == wantedArtist)) {
        return item;
      }
    }
    return null;
  }

  /// Ids and name+artist keys of every song in the main playlist.
  ///
  /// A track with several artists gets one key per artist, so a Last.fm
  /// candidate credited to any of them is recognised.
  Future<({Set<String> ids, Set<String> keys})> _ownedSongs() async {
    final rows = await _db.customSelect(
      'SELECT t.id AS id, t.name AS name, a.name AS artist '
      'FROM tracks t '
      'JOIN track_artists ta ON ta.track_id = t.id '
      'JOIN artists a ON a.id = ta.artist_id',
    ).get();

    final ids = <String>{};
    final keys = <String>{};
    for (final row in rows) {
      ids.add(row.read<String>('id'));
      keys.add(songKey(row.read<String>('name'), row.read<String>('artist')));
    }
    // Tracks without artist rows still count by id.
    final idRows = await (_db.selectOnly(_db.tracks)
          ..addColumns([_db.tracks.id]))
        .get();
    ids.addAll(idRows.map((r) => r.read(_db.tracks.id)!));
    return (ids: ids, keys: keys);
  }

  /// Key used to compare songs across Last.fm, Spotify and the library.
  static String songKey(String name, String artist) =>
      '${normalize(name)}|${normalize(artist)}';

  /// Lower-case, without "(…)" / "[…]" parts, " - Remastered"-style
  /// suffixes, spaces or punctuation.
  ///
  /// `"Starlight - Remastered 2011"` and `"Starlight (Live)"` both become
  /// `"starlight"`. If nothing is left, the lower-cased text is returned.
  static String normalize(String text) {
    final lower = text.toLowerCase().trim();
    final result = lower
        .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ')
        .replaceAll(RegExp(r'\s+-\s+.*$'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
    return result.isEmpty ? lower : result;
  }

  /// Removes quotes so they do not break Spotify's field filters.
  static String _clean(String text) => text.replaceAll('"', '').trim();

  static Track _toTrack(SpotifyPlaylistItemDto item) => Track(
        id: item.id,
        uri: item.uri,
        name: item.name,
        artistIds: [for (final a in item.artists) a.id],
        albumId: item.albumId,
        albumName: item.albumName,
        duration: Duration(milliseconds: item.durationMs),
        releaseDate: item.releaseDate,
        coverUrl: item.coverUrl,
      );
}