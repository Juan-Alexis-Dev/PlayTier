import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/data/services/local/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertTrack(String id) {
    return db.into(db.tracks).insert(
          TracksCompanion.insert(
            id: id,
            uri: 'spotify:track:$id',
            name: 'Track $id',
            albumId: 'album1',
            albumName: 'Album',
            durationMs: 180000,
            position: 0,
          ),
        );
  }

  test('new level defaults to 1', () async {
    await insertTrack('t1');
    await db.into(db.trackLevels).insert(
          TrackLevelsCompanion.insert(trackId: 't1'),
        );

    final row = await db.select(db.trackLevels).getSingle();
    expect(row.level, 1);
  });

  test('level outside 1–5 is rejected', () async {
    await insertTrack('t1');

    expect(
      () => db.into(db.trackLevels).insert(
            TrackLevelsCompanion.insert(trackId: 't1', level: const Value(6)),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a track deletes its level and artist links', () async {
    await insertTrack('t1');
    await db.into(db.artists).insert(
          ArtistsCompanion.insert(id: 'a1', name: 'Artist'),
        );
    await db.into(db.trackArtists).insert(
          TrackArtistsCompanion.insert(
              trackId: 't1', artistId: 'a1', position: 0),
        );
    await db.into(db.trackLevels).insert(
          TrackLevelsCompanion.insert(trackId: 't1', level: const Value(4)),
        );

    await (db.delete(db.tracks)..where((t) => t.id.equals('t1'))).go();

    expect(await db.select(db.trackLevels).get(), isEmpty);
    expect(await db.select(db.trackArtists).get(), isEmpty);
  });
}