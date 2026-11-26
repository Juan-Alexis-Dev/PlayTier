import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/data/repositories/levels_repository.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/domain/models/like_level.dart';
import 'package:playtier/domain/models/result.dart';

void main() {
  late AppDatabase db;
  late LevelsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LevelsRepository(db);
  });
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

  LikeLevel levelOf(Result<LikeLevel> result) => switch (result) {
        Ok(:final value) => value,
        Error(:final error) => throw error,
      };

  test('a track without a level row is level 1', () async {
    await insertTrack('t1');

    expect(levelOf(await repo.getLevel('t1')), LikeLevel.defaultLevel);
  });

  test('setLevel saves the level and getLevel reads it', () async {
    await insertTrack('t1');

    final result = await repo.setLevel('t1', LikeLevel(4));

    expect(result, isA<Ok<void>>());
    expect(levelOf(await repo.getLevel('t1')), LikeLevel(4));
  });

  test('setLevel overwrites an existing level', () async {
    await insertTrack('t1');
    await repo.setLevel('t1', LikeLevel(2));
    await repo.setLevel('t1', LikeLevel(5));

    expect(levelOf(await repo.getLevel('t1')), LikeLevel(5));
    expect(await db.select(db.trackLevels).get(), hasLength(1));
  });

  test('setLevel fails for a track not in the main playlist', () async {
    final result = await repo.setLevel('missing', LikeLevel(3));

    expect(result, isA<Error<void>>());
  });

  test('watchLevels emits the saved level', () async {
    await insertTrack('t1');
    await repo.setLevel('t1', LikeLevel(3));

    expect(await repo.watchLevels().first, {'t1': 3});
  });
}