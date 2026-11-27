import 'package:drift/drift.dart';

import '../../domain/engines/genre_cleaner.dart';
import '../../domain/models/result.dart';
import '../services/lastfm/lastfm_service.dart';
import '../services/local/app_database.dart';
import '../services/local/tables.dart';
import '../services/musicbrainz/musicbrainz_api_exception.dart';
import '../services/musicbrainz/musicbrainz_service.dart';
import '../services/spotify/spotify_api_service.dart';

/// Genres found for one artist and where they came from.
typedef _Found = ({List<String> genres, GenreSource source});

/// Genre enrichment (FR-2.5): Spotify → Last.fm → MusicBrainz.
///
/// The cache is the database: an artist with `genresFetchedAt` set is
/// never queried again, even when no source had genres for it. Artists
/// removed by sync lose their genres through the cascade, and artists
/// added later start pending (`genresFetchedAt` null).
class GenreRepository {
  GenreRepository({
    required this._db,
    required this._spotify,
    required this._musicBrainz,
    this._lastFm,
  });

  final AppDatabase _db;
  final SpotifyApiService _spotify;
  final MusicBrainzService _musicBrainz;

  /// Null when there is no Last.fm API key: that step is skipped.
  final LastFmService? _lastFm;

  /// Last.fm tags below this weight (0–100) are noise.
  static const lastFmMinCount = 10;

  Future<Result<int>>? _running;

  /// Finds genres for every pending artist and saves them one by one, so
  /// the database streams update while it runs.
  ///
  /// Returns how many artists were processed. If MusicBrainz is still
  /// busy after its retries, that artist stays pending and the run goes on
  /// with the next one. Any other error (offline, Spotify) stops the run;
  /// the artists already done stay cached and the rest are retried next
  /// time. Calls while a run is active share it.
  Future<Result<int>> enrichMissing() {
    return _running ??= _enrichMissing().whenComplete(() => _running = null);
  }

  Future<Result<int>> _enrichMissing() async {
    try {
      final pending = await (_db.select(_db.artists)
            ..where((a) => a.genresFetchedAt.isNull()))
          .get();
      var done = 0;
      for (final artist in pending) {
        try {
          final found = await _find(artist.id, artist.name);
          await _save(artist.id, found);
          done++;
        } on MusicBrainzApiException {
          // Server busy: leave it pending (genresFetchedAt stays null).
          continue;
        }
      }
      return Result.ok(done);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Runs the chain for one artist; stops at the first source with genres.
  Future<_Found?> _find(String artistId, String artistName) async {
    final spotify = await _spotify.getArtist(artistId);
    final spotifyGenres = GenreCleaner.clean(
      [for (final genre in spotify.genres) (name: genre, count: 0)],
      artistName: artistName,
      limit: null,
    );
    if (spotifyGenres.isNotEmpty) {
      return (genres: spotifyGenres, source: GenreSource.spotify);
    }

    final lastFm = _lastFm;
    if (lastFm != null) {
      final tags = GenreCleaner.clean(
        await lastFm.getArtistTopTags(artistName),
        artistName: artistName,
        minCount: lastFmMinCount,
      );
      if (tags.isNotEmpty) return (genres: tags, source: GenreSource.lastFm);
    }

    final musicBrainzId = await _musicBrainz.findArtistBySpotifyId(artistId) ??
        await _musicBrainz.searchArtist(artistName);
    if (musicBrainzId != null) {
      final genres = GenreCleaner.clean(
        await _musicBrainz.getArtistGenres(musicBrainzId),
        artistName: artistName,
      );
      if (genres.isNotEmpty) {
        return (genres: genres, source: GenreSource.musicBrainz);
      }
    }
    return null;
  }

  /// Marks the artist as fetched and replaces its genres. Skips artists
  /// that a sync removed meanwhile.
  Future<void> _save(String artistId, _Found? found) {
    return _db.transaction(() async {
      final updated = await (_db.update(_db.artists)
            ..where((a) => a.id.equals(artistId)))
          .write(ArtistsCompanion(genresFetchedAt: Value(DateTime.now())));
      if (updated == 0) return;

      await (_db.delete(_db.artistGenres)
            ..where((g) => g.artistId.equals(artistId)))
          .go();
      if (found == null) return;
      await _db.batch((b) {
        b.insertAll(
          _db.artistGenres,
          [
            for (final genre in found.genres)
              ArtistGenresCompanion.insert(
                artistId: artistId,
                genre: genre,
                source: found.source,
              ),
          ],
          mode: InsertMode.insertOrIgnore,
        );
      });
    });
  }
}