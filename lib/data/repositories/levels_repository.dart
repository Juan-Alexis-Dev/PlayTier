import 'package:drift/drift.dart';

import '../../domain/models/like_level.dart';
import '../../domain/models/result.dart';
import '../services/local/app_database.dart';

/// Like levels 1–5 per track (FR-3).
///
/// Levels are stored only on this device. New tracks get a level 1 row
/// during sync, and removed tracks lose their level through the foreign
/// key cascade (see `LibraryRepository`).
class LevelsRepository {
  LevelsRepository(this._db);

  final AppDatabase _db;

  /// Track id → like level. Tracks without a row are level 1.
  Stream<Map<String, int>> watchLevels() {
    return _db.select(_db.trackLevels).watch().map(
          (rows) => {for (final row in rows) row.trackId: row.level},
        );
  }

  /// Number of tracks with level 2–5 (the Liked page).
  Stream<int> watchLikedCount() {
    final count = _db.trackLevels.trackId.count();
    final query = _db.selectOnly(_db.trackLevels)
      ..addColumns([count])
      ..where(_db.trackLevels.level.isBiggerOrEqualValue(2));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Level of [trackId]. A track without a row is level 1.
  Future<Result<LikeLevel>> getLevel(String trackId) async {
    try {
      final row = await (_db.select(_db.trackLevels)
            ..where((t) => t.trackId.equals(trackId)))
          .getSingleOrNull();
      return Result.ok(
        row == null ? LikeLevel.defaultLevel : LikeLevel(row.level),
      );
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Saves [level] for [trackId] (insert or update).
  ///
  /// The track must be in the main playlist (`tracks` table); otherwise
  /// the foreign key fails and an error is returned.
  Future<Result<void>> setLevel(String trackId, LikeLevel level) async {
    try {
      await _db.into(_db.trackLevels).insertOnConflictUpdate(
            TrackLevelsCompanion.insert(
              trackId: trackId,
              level: Value(level.value),
            ),
          );
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}