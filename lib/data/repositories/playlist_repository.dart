import '../../domain/models/playlist_summary.dart';
import '../../domain/models/result.dart';
import '../services/spotify/spotify_api_service.dart';

/// User and app playlists. Grows in v0.2 (playback and permanent playlists).
class PlaylistRepository {
  PlaylistRepository(this._api);

  final SpotifyApiService _api;

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
}