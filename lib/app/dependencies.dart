import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/genre_repository.dart';
import '../data/repositories/levels_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playback_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/lastfm/lastfm_service.dart';
import '../data/services/local/app_database.dart';
import '../data/services/local/secure_storage_service.dart';
import '../data/services/musicbrainz/musicbrainz_service.dart';
import '../data/services/playback/app_remote_playback_service.dart';
import '../data/services/playback/connect_playback_service.dart';
import '../data/services/playback/playback_service.dart';
import '../data/services/spotify/spotify_api_service.dart';
import '../data/services/spotify/spotify_auth_service.dart';
import '../data/services/spotify/spotify_http_client.dart';
import '../features/player/player_view_model.dart';
import '../features/settings/settings_view_model.dart';
import 'config.dart';

/// Creates services and repositories, loads saved state and returns the
/// providers for the root `MultiProvider`.
Future<List<SingleChildWidget>> buildProviders(AppConfig config) async {
  // Services
  final database = AppDatabase();
  final secureStorage = SecureStorageService();
  final authService = SpotifyAuthService(config);
  // Last.fm and MusicBrainz need no Spotify token: plain client.
  final externalClient = http.Client();
  final lastFmService = config.hasLastFmKey
      ? LastFmService(externalClient, apiKey: config.lastFmApiKey)
      : null;
  final musicBrainzService = MusicBrainzService(externalClient);

  // Repositories
  final authRepository = AuthRepository(
    authService: authService,
    storage: secureStorage,
  );
  final httpClient = SpotifyHttpClient(
    getAccessToken: authRepository.getAccessToken,
    refreshAccessToken: authRepository.refreshAccessToken,
  );
  final apiService = SpotifyApiService(httpClient);
  final PlaybackService playbackService = Platform.isAndroid
      ? AppRemotePlaybackService(config, apiService)
      : ConnectPlaybackService(apiService);
  final settingsRepository = SettingsRepository(database);
  final playlistRepository = PlaylistRepository(api: apiService, db: database);
  final levelsRepository = LevelsRepository(database);
  final libraryRepository = LibraryRepository(
    api: apiService,
    db: database,
    settings: settingsRepository,
  );
  final genreRepository = GenreRepository(
    db: database,
    spotify: apiService,
    musicBrainz: musicBrainzService,
    lastFm: lastFmService,
  );
  final playbackRepository = PlaybackRepository(
    playbackService,
    playlists: playlistRepository,
    levels: levelsRepository,
  );

  // App-wide ViewModels
  final settingsViewModel = SettingsViewModel(settingsRepository);
  final playerViewModel = PlayerViewModel(
    playback: playbackRepository,
    levels: levelsRepository,
    library: libraryRepository,
    loggedIn: authRepository.isLoggedIn,
  );

  await authRepository.init();
  await settingsViewModel.load();
  playerViewModel.init();

  return [
    Provider.value(value: database),
    Provider.value(value: authRepository),
    Provider.value(value: settingsRepository),
    Provider.value(value: playlistRepository),
    Provider.value(value: libraryRepository),
    Provider.value(value: genreRepository),
    Provider.value(value: levelsRepository),
    Provider.value(value: playbackRepository),
    ChangeNotifierProvider.value(value: settingsViewModel),
    ChangeNotifierProvider.value(value: playerViewModel),
  ];
}