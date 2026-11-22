import 'package:drift/drift.dart';

import '../services/local/app_database.dart';

/// Like levels 1–5 per track (FR-3). Grows in v0.3 (get/set levels).
class LevelsRepository {
  LevelsRepository(this._db);

  final AppDatabase _db;

  /// Number of tracks with level 2–5 (the Liked page).
  Stream<int> watchLikedCount() {
    final count = _db.trackLevels.trackId.count();
    final query = _db.selectOnly(_db.trackLevels)
      ..addColumns([count])
      ..where(_db.trackLevels.level.isBiggerOrEqualValue(2));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }
}