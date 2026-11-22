import 'package:drift/drift.dart';

import '../../domain/models/home_playlists_option.dart';
import '../../domain/models/playlist_summary.dart';
import '../../domain/models/result.dart';
import '../services/local/app_database.dart';
import '../services/local/tables.dart';
import '../services/spotify/spotify_api_service.dart';

/// User and app playlists. Grows in v0.2 (playback and permanent playlists).
class PlaylistRepository {
  PlaylistRepository({required this._api, required this._db});

  final SpotifyApiService _api;
  final AppDatabase _db;

  /// Spotify playlists owned by the user (candidates for the main playlist).
  Future<Result<List<PlaylistSummary>>> getOwnedSpotifyPlaylists() async {
    try {
      final userId = await _api.getCurrentUserId();
      final playlists = await _api.getMyPlaylists();
      return Result.ok([
        for (final p in playlists)
          if (p.ownerId == userId)
            PlaylistSummary(
              id: p.id,
              name: p.name,
              trackCount: p.trackCount,
              type: PlaylistType.spotify,
              coverUrl: p.imageUrl,
            ),
      ]);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Playlists for the "Your playlists" grid in Home (FR-1.3).
  ///
  /// Permanent playlists created with the app first (newest first); with
  /// [HomePlaylistsOption.includeSpotify], then the user's other Spotify
  /// playlists, without the main playlist or app playlists.
  Future<Result<List<PlaylistSummary>>> getHomePlaylists({
    required HomePlaylistsOption option,
    String? mainPlaylistId,
  }) async {
    try {
      final appRows = await (_db.select(_db.appPlaylists)
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
          .get();
      final playlists = [
        for (final row in appRows)
          if (row.kind == AppPlaylistKind.permanent)
            PlaylistSummary(
              id: row.id,
              name: row.name,
              trackCount: 0, // Not stored yet (v0.2).
              type: PlaylistType.permanent,
            ),
      ];

      if (option == HomePlaylistsOption.includeSpotify) {
        // App playlists include the private playback playlist: never shown.
        final hiddenIds = {
          for (final row in appRows) row.id,
          ?mainPlaylistId,
        };
        final result = await getOwnedSpotifyPlaylists();
        switch (result) {
          case Ok(:final value):
            playlists.addAll(value.where((p) => !hiddenIds.contains(p.id)));
          case Error(:final error):
            return Result.error(error);
        }
      }
      return Result.ok(playlists);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}