import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/playlist_repository.dart';
import 'package:playtier/data/services/local/app_database.dart';
import 'package:playtier/data/services/spotify/spotify_api_exception.dart';
import 'package:playtier/data/services/spotify/spotify_api_service.dart';
import 'package:playtier/domain/models/result.dart';

class MockSpotify extends Mock implements SpotifyApiService {}

void main() {
  late AppDatabase db;
  late MockSpotify api;
  late PlaylistRepository repo;

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = MockSpotify();
    repo = PlaylistRepository(api: api, db: db);
  });
  tearDown(() => db.close());

  test('addTracks appends the tracks to that playlist', () async {
    when(() => api.addPlaylistItems(any(), any())).thenAnswer((_) async {});

    final result = await repo.addTracks('perm1', ['spotify:track:t1']);

    expect(result, isA<Ok<void>>());
    verify(() => api.addPlaylistItems('perm1', ['spotify:track:t1']))
        .called(1);
  });

  test('addTracks returns an error when Spotify fails', () async {
    when(() => api.addPlaylistItems(any(), any()))
        .thenThrow(const SpotifyApiException(403, 'forbidden'));

    final result = await repo.addTracks('perm1', ['spotify:track:t1']);

    expect(result, isA<Error<void>>());
  });
}