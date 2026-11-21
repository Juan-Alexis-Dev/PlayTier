import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database (drift).
///
/// After changing a table, bump [schemaVersion], add the step in
/// [migration] and regenerate:
///
/// ```bash
/// dart run build_runner build --delete-conflicting-outputs
/// ```
@DriftDatabase(
  tables: [
    Tracks,
    Artists,
    TrackArtists,
    ArtistGenres,
    TrackLevels,
    SyncState,
    LyricsCache,
    Palettes,
    Settings,
    AppPlaylists,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the app database file. Pass an [executor] in tests
  /// (e.g. `NativeDatabase.memory()`).
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'playtier'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // Version 1: create every table.
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          // SQLite ignores foreign keys (and cascades) unless enabled.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}