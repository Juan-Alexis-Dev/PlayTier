import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/settings_repository.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/result.dart';

class MockApi extends Mock implements SpotifyApiService {}

class MockSettings extends Mock implements SettingsRepository {}

void main() {
  late AppDatabase db;
  late MockApi api;
  late MockSettings settings;
  late LibraryRepository repo;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = MockApi();
    settings = MockSettings();
    repo = LibraryRepository(api: api, db: db, settings: settings);

    when(settings.getMainPlaylistId).thenAnswer((_) async => 'main1');
    when(() => api.addPlaylistItems(any(), any())).thenAnswer((_) async {});
    // The sync after adding is not under test here; it fails quietly.
    when(() => api.getPlaylistInfo(any())).thenThrow(Exception('offline'));
  });
  tearDown(() => db.close());

  group('addToMain', () {
    test('adds the track to the main playlist and syncs', () async {
      final result = await repo.addToMain('spotify:track:t1');

      expect(result, isA<Ok<void>>());
      verify(() => api.addPlaylistItems('main1', ['spotify:track:t1']))
          .called(1);
      verify(() => api.getPlaylistInfo('main1')).called(1);
    });

    test('a failed sync after adding is still ok', () async {
      expect(await repo.addToMain('spotify:track:t1'), isA<Ok<void>>());
    });

    test('does not add a track already in the main playlist', () async {
      await db.into(db.tracks).insert(
            TracksCompanion.insert(
              id: 't1',
              uri: 'spotify:track:t1',
              name: 'Track',
              albumId: 'album1',
              albumName: 'Album',
              durationMs: 180000,
              position: 0,
            ),
          );

      expect(await repo.addToMain('spotify:track:t1'), isA<Ok<void>>());
      verifyNever(() => api.addPlaylistItems(any(), any()));
    });

    test('fails without a main playlist', () async {
      when(settings.getMainPlaylistId).thenAnswer((_) async => null);

      expect(await repo.addToMain('spotify:track:t1'), isA<Error<void>>());
      verifyNever(() => api.addPlaylistItems(any(), any()));
    });

    test('a Spotify error is returned', () async {
      when(() => api.addPlaylistItems(any(), any()))
          .thenThrow(Exception('403'));

      expect(await repo.addToMain('spotify:track:t1'), isA<Error<void>>());
    });
  });
}