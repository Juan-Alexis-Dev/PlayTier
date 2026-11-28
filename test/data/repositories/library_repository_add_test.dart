import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/library_repository.dart';
import 'package:playtier/data/repositories/settings_repository.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/spotify/dto/spotify_artist_dto.dart';
import 'package:playtier/data/services/spotify/dto/spotify_playlist_dto.dart';
import 'package:playtier/data/services/spotify/dto/spotify_playlist_item_dto.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/result.dart';

class MockApi extends Mock implements SpotifyApiService {}

class MockSettings extends Mock implements SettingsRepository {}

const uri = 'spotify:track:t1';

SpotifyPlaylistDto info(String snapshot) => SpotifyPlaylistDto(
      id: 'main1',
      name: 'Main',
      ownerId: 'me',
      trackCount: 1,
      snapshotId: snapshot,
    );

const item = SpotifyPlaylistItemDto(
  id: 't1',
  uri: uri,
  name: 'Song',
  durationMs: 1000,
  albumId: 'al',
  albumName: 'Album',
  artists: [SpotifyArtistDto(id: 'a1', name: 'Muse')],
);

/// Adding a track twice before the sync shows it must not add it twice
/// (Spotify can report the old snapshot for a moment after an add).
void main() {
  late AppDatabase db;
  late MockApi api;
  late MockSettings settings;
  late LibraryRepository repo;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = MockApi();
    settings = MockSettings();
    repo = LibraryRepository(
      api: api,
      db: db,
      settings: settings,
      addSyncRetries: const [],
    );

    when(settings.getMainPlaylistId).thenAnswer((_) async => 'main1');
    when(() => settings.setMainPlaylistInfo(
          name: any(named: 'name'),
          coverUrl: any(named: 'coverUrl'),
        )).thenAnswer((_) async {});
    when(() => api.addPlaylistItems(any(), any())).thenAnswer((_) async {});
    // Stale snapshot: the sync sees no change, so t1 is not local yet.
    await db.into(db.syncState).insert(SyncStateCompanion.insert(
          playlistId: 'main1',
          snapshotId: 's1',
          lastSyncedAt: DateTime(2026),
        ));
    when(() => api.getPlaylistInfo(any())).thenAnswer((_) async => info('s1'));
  });
  tearDown(() => db.close());

  test('a second add while waiting for the sync does not add again',
      () async {
    expect(await repo.addToMain(uri), isA<Ok<void>>());
    expect(repo.isPendingAdd(uri), isTrue);

    expect(await repo.addToMain(uri), isA<Ok<void>>());

    verify(() => api.addPlaylistItems('main1', [uri])).called(1);
  });

  test('parallel taps share one request', () async {
    final gate = Completer<void>();
    when(() => api.addPlaylistItems(any(), any()))
        .thenAnswer((_) => gate.future);

    final first = repo.addToMain(uri);
    final second = repo.addToMain(uri);
    gate.complete();
    await Future.wait([first, second]);

    verify(() => api.addPlaylistItems('main1', [uri])).called(1);
  });

  test('a failed add is not pending, so it can be retried', () async {
    when(() => api.addPlaylistItems(any(), any()))
        .thenThrow(Exception('offline'));

    expect(await repo.addToMain(uri), isA<Error<void>>());
    expect(repo.isPendingAdd(uri), isFalse);

    when(() => api.addPlaylistItems(any(), any())).thenAnswer((_) async {});
    expect(await repo.addToMain(uri), isA<Ok<void>>());
    verify(() => api.addPlaylistItems('main1', [uri])).called(2);
  });

  test('a sync that brings the track clears the pending add', () async {
    await repo.addToMain(uri);
    expect(repo.isPendingAdd(uri), isTrue);

    when(() => api.getPlaylistInfo(any())).thenAnswer((_) async => info('s2'));
    when(() => api.getPlaylistItems(any())).thenAnswer((_) async => [item]);
    await repo.syncIfChanged();

    expect(repo.isPendingAdd(uri), isFalse);
  });

  test('a manual sync clears pending adds that never showed up', () async {
    await repo.addToMain(uri);
    when(() => api.getPlaylistItems(any())).thenAnswer((_) async => []);

    await repo.syncIfChanged(force: true);

    expect(repo.isPendingAdd(uri), isFalse);
  });

  test('retries the sync until the track shows up', () async {
    final retrying = LibraryRepository(
      api: api,
      db: db,
      settings: settings,
      addSyncRetries: const [Duration.zero, Duration.zero],
    );
    var checks = 0;
    when(() => api.getPlaylistInfo(any())).thenAnswer((_) async {
      checks++;
      // The first check right after the add is stale; the retry is not.
      return info(checks == 1 ? 's1' : 's2');
    });
    when(() => api.getPlaylistItems(any())).thenAnswer((_) async => [item]);

    await retrying.addToMain(uri);
    expect(retrying.isPendingAdd(uri), isTrue);

    // Let the retries (zero delays) and the database writes run.
    for (var i = 0; i < 50 && retrying.isPendingAdd(uri); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(retrying.isPendingAdd(uri), isFalse);
    // Stops once the track is local: no second retry.
    expect(checks, 2);
  });
}