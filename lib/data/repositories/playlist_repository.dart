import 'package:drift/drift.dart';

import '../../domain/models/home_playlists_option.dart';
import '../../domain/models/playlist_summary.dart';
import '../../domain/models/result.dart';
import '../services/local/app_database.dart';
import '../services/local/tables.dart';
import '../services/spotify/spotify_api_exception.dart';
import '../services/spotify/spotify_api_service.dart';

/// User and app playlists: the user's Spotify playlists, the private
/// playback playlist (FR-1.6) and permanent playlists created with the app.
class PlaylistRepository {
  PlaylistRepository({required this._api, required this._db});

  final SpotifyApiService _api;
  final AppDatabase _db;

  /// Name of the private playlist where temporary lists are written.
  static const playbackPlaylistName = 'PlayTier — Playback';

  /// Id of the private playback playlist (FR-1.6).
  ///
  /// Uses the saved one; otherwise reuses a playlist of the user with
  /// [playbackPlaylistName] (e.g. after a reinstall) or creates it.
  Future<Result<String>> ensurePlaybackPlaylist() => _guard(_playbackId);

  /// Replaces the playback playlist with [uris], in order, and returns its
  /// context URI (`spotify:playlist:<id>`) to pass to
  /// `PlaybackRepository.playList()`. Duplicates are kept (weighted shuffle).
  ///
  /// If the saved playlist no longer exists, a new one is created once.
  Future<Result<String>> writePlaybackPlaylist(List<String> uris) {
    return _guard(() async {
      var id = await _playbackId();
      try {
        await _api.replacePlaylistItems(id, uris);
      } on SpotifyApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        await (_db.delete(_db.appPlaylists)..where((p) => p.id.equals(id)))
            .go();
        id = await _playbackId(searchSpotify: false);
        await _api.replacePlaylistItems(id, uris);
      }
      return 'spotify:playlist:$id';
    });
  }

  /// Creates a real, private playlist in the user's Spotify account with
  /// [uris] in order (FR-8.2) and saves it as a permanent app playlist.
  Future<Result<PlaylistSummary>> createPermanent(
    String name,
    List<String> uris,
  ) {
    return _guard(() async {
      final created = await _api.createPlaylist(
        name,
        description: 'Created with PlayTier.',
      );
      await _api.addPlaylistItems(created.id, uris);
      await _save(created.id, name, AppPlaylistKind.permanent);
      return PlaylistSummary(
        id: created.id,
        name: name,
        trackCount: uris.length,
        type: PlaylistType.permanent,
      );
    });
  }

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

  Future<String> _playbackId({bool searchSpotify = true}) async {
    final saved = await (_db.select(_db.appPlaylists)
          ..where((p) => p.kind.equalsValue(AppPlaylistKind.playback))
          ..limit(1))
        .getSingleOrNull();
    if (saved != null) return saved.id;

    String? id;
    if (searchSpotify) {
      final userId = await _api.getCurrentUserId();
      final playlists = await _api.getMyPlaylists();
      id = playlists
          .where((p) => p.ownerId == userId && p.name == playbackPlaylistName)
          .firstOrNull
          ?.id;
    }
    id ??= (await _api.createPlaylist(
      playbackPlaylistName,
      description: 'Used by PlayTier to play lists in order. '
          'Its content is replaced every time.',
    ))
        .id;

    await _save(id, playbackPlaylistName, AppPlaylistKind.playback);
    return id;
  }

  Future<void> _save(String id, String name, AppPlaylistKind kind) {
    return _db.into(_db.appPlaylists).insertOnConflictUpdate(
          AppPlaylistsCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Result.ok(await action());
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}