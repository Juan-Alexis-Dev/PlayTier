import '../../domain/models/home_playlists_option.dart';
import '../services/local/app_database.dart';

/// App settings stored as key-value rows in the `settings` table.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _mainPlaylistIdKey = 'main_playlist_id';
  static const _homePlaylistsKey = 'home_playlists';
  static const _paletteKey = 'palette';
  static const _onboardingDoneKey = 'onboarding_done';

  Future<String?> getMainPlaylistId() => _get(_mainPlaylistIdKey);

  Future<void> setMainPlaylistId(String id) => _set(_mainPlaylistIdKey, id);

  /// Defaults to [HomePlaylistsOption.appOnly] when not set.
  Future<HomePlaylistsOption> getHomePlaylistsOption() async {
    final value = await _get(_homePlaylistsKey);
    return HomePlaylistsOption.values.asNameMap()[value] ??
        HomePlaylistsOption.appOnly;
  }

  Future<void> setHomePlaylistsOption(HomePlaylistsOption option) =>
      _set(_homePlaylistsKey, option.name);

  /// Name of the selected palette, or null for the default.
  Future<String?> getPaletteName() => _get(_paletteKey);

  Future<void> setPaletteName(String name) => _set(_paletteKey, name);

  Future<bool> isOnboardingDone() async =>
      await _get(_onboardingDoneKey) == 'true';

  Future<void> setOnboardingDone(bool done) =>
      _set(_onboardingDoneKey, '$done');

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }
}