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

  /// Discover needs Last.fm; the UI hides it when this is false.
  bool get isAvailable => _lastFm != null;

  /// Mode 1, "New music from your artists" (FR-10.1).
  ///
  /// Takes the [artistsPerRun] main artists with the most tracks in the
  /// main playlist, asks Last.fm for each one's top tracks, drops the ones
  /// already owned and mixes the rest one artist at a time (most popular
  /// first), so no artist fills the whole list.
  Future<Result<PlaylistDraft>> newFromYourArtists({
    int maxTracks = defaultMaxTracks,
  }) async {
    final lastFm = _lastFm;
    if (lastFm == null) return Result.error(_noLastFm);

    try {
      final artists = await _topArtistNames(artistsPerRun);
      final topTracks = await Future.wait([
        for (final artist in artists)
          lastFm.getArtistTopTracks(artist, limit: tracksPerArtist),
      ]);
      // Drop owned tracks before mixing, so every artist keeps its turn.
      final owned = (await _ownedSongs()).keys;
      final fresh = [
        for (final list in topTracks)
          [
            for (final t in list)
              if (!owned.contains(songKey(t.name, t.artist))) t,
          ],
      ];
      return _draft(
        DiscoverMode.fromArtists,
        await matchTracks(interleave(fresh), maxTracks: maxTracks),
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
        )),
      Error(:final error) => Result.error(error),
    };
  }

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