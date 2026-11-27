import '../models/track.dart';
import 'facet_counter.dart';

/// Card data of a genre or artist virtual playlist (FR-6).
///
/// [id] is the genre name (lower-case) or the Spotify artist id;
/// [coverUrls] are up to 4 distinct track covers, for the mosaic.
typedef VirtualPlaylist = ({
  String id,
  String name,
  int trackCount,
  List<String> coverUrls,
});

/// Builds the Genres and Artists pages from the main playlist (FR-6).
/// Pure Dart, no I/O.
///
/// Order and counts come from [FacetCounter]: most tracks first, ties by
/// name. Covers are taken in playlist order.
abstract final class VirtualPlaylists {
  /// Covers per card (a 2×2 mosaic).
  static const maxCovers = 4;

  /// One playlist per genre. A track's genres are the union of its
  /// artists' genres, so it can appear in several playlists (FR-6.1).
  static List<VirtualPlaylist> genres(
    List<Track> tracks,
    Map<String, List<String>> genresByArtist,
  ) {
    final covers = <String, List<String>>{};
    for (final track in tracks) {
      final trackGenres = {
        for (final id in track.artistIds) ...?genresByArtist[id],
      };
      for (final genre in trackGenres) {
        _addCover(covers, genre, track.coverUrl);
      }
    }
    return [
      for (final facet in FacetCounter.genres(tracks, genresByArtist))
        (
          id: facet.value,
          name: genreName(facet.value),
          trackCount: facet.count,
          coverUrls: covers[facet.value] ?? const [],
        ),
    ];
  }

  /// One playlist per artist, featured artists included (FR-6.2).
  /// Unknown names fall back to the artist id.
  static List<VirtualPlaylist> artists(
    List<Track> tracks,
    Map<String, String> artistNames,
  ) {
    final covers = <String, List<String>>{};
    for (final track in tracks) {
      for (final id in track.artistIds.toSet()) {
        _addCover(covers, id, track.coverUrl);
      }
    }
    return [
      for (final facet
          in FacetCounter.artists(tracks, artistNames: artistNames))
        (
          id: facet.value,
          name: artistNames[facet.value] ?? facet.value,
          trackCount: facet.count,
          coverUrls: covers[facet.value] ?? const [],
        ),
    ];
  }

  static void _addCover(
    Map<String, List<String>> covers,
    String key,
    String? url,
  ) {
    if (url == null) return;
    final list = covers.putIfAbsent(key, () => []);
    if (list.length < maxCovers && !list.contains(url)) list.add(url);
  }

  /// Display name of a genre: "rock en español" → "Rock en español".
  static String genreName(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}