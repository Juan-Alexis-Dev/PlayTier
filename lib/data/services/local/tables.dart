import 'package:drift/drift.dart';

// Data classes use the `Row` suffix so they never clash with domain models
// (`Track`, `Artist`, `Palette`). Repositories map rows → domain models.

/// Where an artist genre came from (enrichment chain, FR-5).
enum GenreSource { spotify, lastFm, musicBrainz }

/// Kind of Spotify playlist created by the app.
enum AppPlaylistKind {
  /// The single private playlist used for weighted shuffle and temporary lists.
  playback,

  /// A playlist the user chose to keep (shown in Home).
  permanent,
}

/// Tracks of the main playlist.
@DataClassName('TrackRow')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get uri => text()();
  TextColumn get name => text()();
  TextColumn get albumId => text()();
  TextColumn get albumName => text()();
  IntColumn get durationMs => integer()();

  /// `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, as Spotify returns it.
  TextColumn get releaseDate => text().nullable()();
  DateTimeColumn get addedAt => dateTime().nullable()();
  TextColumn get coverUrl => text().nullable()();

  /// Index in the main playlist (default order).
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Artists of the tracks in the main playlist.
@DataClassName('ArtistRow')
class Artists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// When genre enrichment last ran; null = never (pending).
  DateTimeColumn get genresFetchedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Many-to-many link between tracks and artists.
@DataClassName('TrackArtistRow')
class TrackArtists extends Table {
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get artistId =>
      text().references(Artists, #id, onDelete: KeyAction.cascade)();

  /// Artist order inside the track (0 = main artist).
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {trackId, artistId};
}

/// Genres of each artist.
@DataClassName('ArtistGenreRow')
class ArtistGenres extends Table {
  TextColumn get artistId =>
      text().references(Artists, #id, onDelete: KeyAction.cascade)();

  /// Lower-case genre name.
  TextColumn get genre => text()();
  TextColumn get source => textEnum<GenreSource>()();

  @override
  Set<Column> get primaryKey => {artistId, genre};
}

/// Like level 1–5 per track. Deleted with the track (FR-2.4).
@DataClassName('TrackLevelRow')
class TrackLevels extends Table {
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();

  // drift needs the column itself inside check(); not a real recursion.
  IntColumn get level => integer()
      .withDefault(const Constant(1))
        // ignore: recursive_getters
      .check(level.isBetweenValues(1, 5))();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Last synced `snapshot_id` per Spotify playlist.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get playlistId => text()();
  TextColumn get snapshotId => text()();
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {playlistId};
}

/// LRCLIB results. Both lyrics null = "no lyrics found" (avoids re-querying).
///
/// No foreign key: Discover tracks are not in [Tracks].
@DataClassName('LyricsCacheRow')
class LyricsCache extends Table {
  TextColumn get trackId => text()();
  TextColumn get syncedLyrics => text().nullable()();
  TextColumn get plainLyrics => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Imported palettes. Presets live in code (`preset_palettes.dart`).
///
/// Colors are ARGB integers, like the domain `Palette`.
@DataClassName('PaletteRow')
class Palettes extends Table {
  TextColumn get name => text()();
  IntColumn get seed => integer()();
  IntColumn get background => integer().nullable()();
  IntColumn get surface => integer().nullable()();
  IntColumn get lyricsHighlight => integer().nullable()();

  @override
  Set<Column> get primaryKey => {name};
}

/// Key-value app settings (main playlist id, palette, lyrics on/off…).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Spotify playlists created by the app.
@DataClassName('AppPlaylistRow')
class AppPlaylists extends Table {
  /// Spotify playlist id.
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<AppPlaylistKind>()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}