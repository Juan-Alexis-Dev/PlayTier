import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/local/app_database.dart';
import '../data/services/local/secure_storage_service.dart';
import '../data/services/spotify/spotify_api_service.dart';
import '../data/services/spotify/spotify_auth_service.dart';
import '../data/services/spotify/spotify_http_client.dart';
import '../features/settings/settings_view_model.dart';
import 'config.dart';

/// Creates services and repositories, loads saved state and returns the
/// providers for the root `MultiProvider`.
Future<List<SingleChildWidget>> buildProviders(AppConfig config) async {
  // Services
  final database = AppDatabase();
  final secureStorage = SecureStorageService();
  final authService = SpotifyAuthService(config);

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
  final settingsRepository = SettingsRepository(database);
  final playlistRepository = PlaylistRepository(apiService);

  // App-wide ViewModels
  final settingsViewModel = SettingsViewModel(settingsRepository);

  await authRepository.init();
  await settingsViewModel.load();

  return [
    Provider.value(value: database),
    Provider.value(value: authRepository),
    Provider.value(value: settingsRepository),
    Provider.value(value: playlistRepository),
    ChangeNotifierProvider.value(value: settingsViewModel),
  ];
}