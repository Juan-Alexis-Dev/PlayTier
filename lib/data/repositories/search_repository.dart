import '../../domain/models/result.dart';
import '../../domain/models/search_result.dart';
import '../../domain/models/track.dart';
import '../services/local/app_database.dart';
import '../services/spotify/dto/spotify_playlist_item_dto.dart';
import '../services/spotify/spotify_api_service.dart';

/// Spotify track search with the "already in main" flag (FR-12).
class SearchRepository {
  SearchRepository({required this._api, required this._db});

  final SpotifyApiService _api;
  final AppDatabase _db;

  /// Searches Spotify for tracks matching [query].
  ///
  /// Each result says whether the track is already in the main playlist
  /// (compared by track id with the local copy). An empty or blank
  /// [query] returns an empty list without calling Spotify.
  Future<Result<List<SearchResult>>> search(
    String query, {
    int offset = 0,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return const Result.ok([]);

    try {
      final items = await _api.searchTracks(text, offset: offset);
      final inMain = await _idsInMain(items.map((t) => t.id).toSet());
      return Result.ok([
        for (final item in items)
          SearchResult(
            track: _toTrack(item),
            artistNames: [for (final a in item.artists) a.name],
            inMain: inMain.contains(item.id),
          ),
      ]);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// The subset of [ids] that are in the local main playlist.
  Future<Set<String>> _idsInMain(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final query = _db.selectOnly(_db.tracks)
      ..addColumns([_db.tracks.id])
      ..where(_db.tracks.id.isIn(ids));
    final rows = await query.get();
    return {for (final row in rows) row.read(_db.tracks.id)!};
  }

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