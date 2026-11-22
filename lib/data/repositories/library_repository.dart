import 'package:drift/drift.dart';

import '../../domain/models/result.dart';
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
  });

  final SpotifyApiService _api;
  final AppDatabase _db;
  final SettingsRepository _settings;

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

      final snapshotId = await _api.getPlaylistSnapshotId(playlistId);
      final state = await (_db.select(_db.syncState)
            ..where((s) => s.playlistId.equals(playlistId)))
          .getSingleOrNull();
      if (!force && state?.snapshotId == snapshotId) {
        return const Result.ok(false);
      }

      final items = await _api.getPlaylistItems(playlistId);
      await _write(playlistId, snapshotId, items);
      return const Result.ok(true);
    } on Exception catch (e) {
      return Result.error(e);
    }
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