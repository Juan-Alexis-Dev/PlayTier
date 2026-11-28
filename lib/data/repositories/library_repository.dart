import 'dart:async';

import 'package:drift/drift.dart';

import '../../domain/engines/virtual_playlists.dart';
import '../../domain/models/result.dart';
import '../../domain/models/track.dart';
import '../services/local/app_database.dart';
import '../services/spotify/dto/spotify_playlist_item_dto.dart';
import '../services/spotify/spotify_api_service.dart';
import 'settings_repository.dart';

/// Local copy of the main playlist (FR-2).
class LibraryRepository {
  LibraryRepository({
    required this._api,
    required this._db,
    required this._settings,
    this.addSyncRetries = const [Duration(seconds: 3), Duration(seconds: 10)],
  });

  /// Waits before re-checking the sync when an added track did not show
  /// up yet. Tests pass an empty list.
  final List<Duration> addSyncRetries;

  final SpotifyApiService _api;
  final AppDatabase _db;
  final SettingsRepository _settings;

  /// Tracks added in this session that the local copy does not have yet.
  /// Spotify can report the old `snapshot_id` for a moment after an add,
  /// so the sync may not bring the track in right away; without this, a
  /// second tap would add it again.
  final Set<String> _pendingAdds = {};

  /// Adds in progress, so parallel taps share one request.
  final Map<String, Future<Result<void>>> _addsInFlight = {};

  /// Tracks of the main playlist in playlist order. Emits again whenever
  /// a sync changes the database.
  Stream<List<Track>> watchTracks() =>
      _tracksQuery().watch().map(_groupTracks);

  /// Genre virtual playlists (FR-6.1), most tracks first. Emits again
  /// after every sync and every artist saved by genre enrichment.
  Stream<List<VirtualPlaylist>> watchGenrePlaylists() => _watchLibrary(
        (tracks, names, genres) => VirtualPlaylists.genres(tracks, genres),
      );

  /// Artist virtual playlists (FR-6.2), most tracks first.
  Stream<List<VirtualPlaylist>> watchArtistPlaylists() => _watchLibrary(
        (tracks, names, genres) => VirtualPlaylists.artists(tracks, names),
      );

  /// Number of tracks in the main playlist.
  Stream<int> watchTrackCount() {
    final count = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Artist id → name, for displaying tracks.
  Stream<Map<String, String>> watchArtistNames() {
    return _db.select(_db.artists).watch().map(
          (rows) => {for (final artist in rows) artist.id: artist.name},
        );
  }

  /// Artist id → genres (filled by genre enrichment, v0.4). Artists
  /// without genres are not in the map.
  Stream<Map<String, List<String>>> watchArtistGenres() {
    return _db.select(_db.artistGenres).watch().map((rows) {
      final genres = <String, List<String>>{};
      for (final row in rows) {
        genres.putIfAbsent(row.artistId, () => []).add(row.genre);
      }
      return genres;
    });
  }

  /// Name and cover of the main playlist (saved on every sync check).
  Future<({String? name, String? coverUrl})> getMainPlaylistInfo() =>
      _settings.getMainPlaylistInfo();

  /// Adds [trackUri] to the end of the main playlist in Spotify, then
  /// syncs so it appears here with level 1 (FR-12.4, FR-2.3).
  ///
  /// Does nothing if the track is already in the main playlist, or was
  /// already added in this session and is waiting for a sync. Parallel
  /// calls for the same track share one request. If only the sync fails,
  /// the result is still ok: the next sync brings it in.
  Future<Result<void>> addToMain(String trackUri) {
    // Block body on purpose: `=> _addsInFlight.remove(...)` would return
    // this same future, and whenComplete would wait for itself forever.
    return _addsInFlight[trackUri] ??=
        _addToMain(trackUri).whenComplete(() {
      _addsInFlight.remove(trackUri);
    });
  }

  /// Whether [trackUri] was added in this session and the local copy does
  /// not show it yet.
  bool isPendingAdd(String trackUri) => _pendingAdds.contains(trackUri);

  Future<Result<void>> _addToMain(String trackUri) async {
    try {
      final playlistId = await _settings.getMainPlaylistId();
      if (playlistId == null) {
        return Result.error(Exception('No main playlist selected'));
      }

      final existing = await (_db.select(_db.tracks)
            ..where((t) => t.uri.equals(trackUri))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        _pendingAdds.remove(trackUri);
        return const Result.ok(null);
      }
      if (_pendingAdds.contains(trackUri)) return const Result.ok(null);

      await _api.addPlaylistItems(playlistId, [trackUri]);
      _pendingAdds.add(trackUri);
      await syncIfChanged();
      if (_pendingAdds.contains(trackUri)) unawaited(_retrySync(trackUri));
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Syncs again after each of [addSyncRetries] until [trackUri] is in the
  /// local copy. Errors are ignored: a later sync brings it in.
  Future<void> _retrySync(String trackUri) async {
    for (final delay in addSyncRetries) {
      await Future<void>.delayed(delay);
      if (!_pendingAdds.contains(trackUri)) return;
      await syncIfChanged();
    }
  }

  /// Syncs the main playlist only if its `snapshot_id` changed (FR-2.2).
  ///
  /// Returns `true` if the local copy was rewritten, `false` if it was
  /// already up to date. [force] skips the snapshot check (manual sync).
  Future<Result<bool>> syncIfChanged({bool force = false}) async {
    try {
      final playlistId = await _settings.getMainPlaylistId();
      if (playlistId == null) {
        return Result.error(Exception('No main playlist selected'));
      }

      final info = await _api.getPlaylistInfo(playlistId);
      await _settings.setMainPlaylistInfo(
        name: info.name,
        coverUrl: info.imageUrl,
      );

      final snapshotId = info.snapshotId;
      final state = await (_db.select(_db.syncState)
            ..where((s) => s.playlistId.equals(playlistId)))
          .getSingleOrNull();
      if (!force && snapshotId != null && state?.snapshotId == snapshotId) {
        return const Result.ok(false);
      }

      final items = await _api.getPlaylistItems(playlistId);
      await _write(playlistId, snapshotId ?? '', items);
      // A full read is the truth: added tracks are no longer pending
      // (and a manual sync lets a track removed in Spotify be added again).
      if (force) {
        _pendingAdds.clear();
      } else {
        _pendingAdds.removeAll(items.map((item) => item.uri));
      }
      return const Result.ok(true);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Tracks joined with their artist links, in playlist order.
    JoinedSelectStatement<HasResultSet, dynamic> _tracksQuery() {
    return _db.select(_db.tracks).join([
      leftOuterJoin(
        _db.trackArtists,
        _db.trackArtists.trackId.equalsExp(_db.tracks.id),
      ),
    ])
      ..orderBy([
        OrderingTerm.asc(_db.tracks.position),
        OrderingTerm.asc(_db.trackArtists.position),
      ]);
  }

  /// One row per (track, artist): groups them, keeping the order.
  List<Track> _groupTracks(List<TypedResult> rows) {
    final tracks = <String, TrackRow>{};
    final artistIds = <String, List<String>>{};
    for (final row in rows) {
      final track = row.readTable(_db.tracks);
      tracks.putIfAbsent(track.id, () => track);
      final ids = artistIds.putIfAbsent(track.id, () => []);
      final link = row.readTableOrNull(_db.trackArtists);
      if (link != null) ids.add(link.artistId);
    }
    return [
      for (final track in tracks.values) _toTrack(track, artistIds[track.id]!),
    ];
  }

  /// Reads tracks, artist names and genres now and again whenever one of
  /// their tables changes, and maps them with [build].
  Stream<T> _watchLibrary<T>(
    T Function(
      List<Track> tracks,
      Map<String, String> artistNames,
      Map<String, List<String>> genresByArtist,
    ) build,
  ) {
    // A tiny query only used as a trigger: drift re-runs it (and emits)
    // on every change to these tables. `asyncMap` keeps the order.
    final trigger = _db.customSelect(
      'SELECT 1',
      readsFrom: {
        _db.tracks,
        _db.trackArtists,
        _db.artists,
        _db.artistGenres,
      },
    ).watch();

    return trigger.asyncMap((_) async {
      final tracks = _groupTracks(await _tracksQuery().get());
      final artists = await _db.select(_db.artists).get();
      final genreRows = await _db.select(_db.artistGenres).get();
      final genres = <String, List<String>>{};
      for (final row in genreRows) {
        genres.putIfAbsent(row.artistId, () => []).add(row.genre);
      }
      return build(
        tracks,
        {for (final artist in artists) artist.id: artist.name},
        genres,
      );
    });
  }

  static Track _toTrack(TrackRow row, List<String> artistIds) {
    return Track(
      id: row.id,
      uri: row.uri,
      name: row.name,
      artistIds: artistIds,
      albumId: row.albumId,
      albumName: row.albumName,
      duration: Duration(milliseconds: row.durationMs),
      releaseDate: row.releaseDate,
      addedAt: row.addedAt,
      coverUrl: row.coverUrl,
    );
  }

  /// Replaces the local copy in one transaction (a batch).
  Future<void> _write(
    String playlistId,
    String snapshotId,
    List<SpotifyPlaylistItemDto> items,
  ) {
    // A track can appear twice in a playlist: keep its first position.
    final tracks = <String, SpotifyPlaylistItemDto>{};
    for (final item in items) {
      tracks.putIfAbsent(item.id, () => item);
    }
    final trackIds = tracks.keys.toList();
    final artistNames = {
      for (final track in tracks.values)
        for (final artist in track.artists) artist.id: artist.name,
    };
    var position = 0;

    return _db.batch((b) {
      // Removed tracks: the cascade deletes their level and artist links
      // (FR-2.4).
      b.deleteWhere(_db.tracks, (t) => t.id.isNotIn(trackIds));

      // Upserts (not REPLACE, which would delete and cascade the levels).
      // Existing artists keep their `genresFetchedAt`.
      b.insertAllOnConflictUpdate(_db.artists, [
        for (final entry in artistNames.entries)
          ArtistsCompanion.insert(id: entry.key, name: entry.value),
      ]);
      b.insertAllOnConflictUpdate(_db.tracks, [
        for (final track in tracks.values)
          TracksCompanion.insert(
            id: track.id,
            uri: track.uri,
            name: track.name,
            albumId: track.albumId,
            albumName: track.albumName,
            durationMs: track.durationMs,
            releaseDate: Value(track.releaseDate),
            addedAt: Value(track.addedAt),
            coverUrl: Value(track.coverUrl),
            position: position++,
          ),
      ]);

      b.deleteAll(_db.trackArtists);
      b.insertAll(
        _db.trackArtists,
        [
          for (final track in tracks.values)
            for (final (index, artist) in track.artists.indexed)
              TrackArtistsCompanion.insert(
                trackId: track.id,
                artistId: artist.id,
                position: index,
              ),
        ],
        mode: InsertMode.insertOrIgnore,
      );

      // New tracks start at level 1; existing levels are kept (FR-2.3).
      b.insertAll(
        _db.trackLevels,
        [for (final id in trackIds) TrackLevelsCompanion.insert(trackId: id)],
        mode: InsertMode.insertOrIgnore,
      );

      // Artists no longer used by any track (their genres cascade).
      b.customStatement(
        'DELETE FROM artists '
        'WHERE id NOT IN (SELECT artist_id FROM track_artists)',
      );

      b.insertAllOnConflictUpdate(_db.syncState, [
        SyncStateCompanion.insert(
          playlistId: playlistId,
          snapshotId: snapshotId,
          lastSyncedAt: DateTime.now(),
        ),
      ]);
    });
  }
}