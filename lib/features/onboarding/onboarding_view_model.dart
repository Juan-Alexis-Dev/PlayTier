import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../domain/models/home_playlists_option.dart';
import '../../domain/models/palette.dart';
import '../../domain/models/playlist_summary.dart';
import '../../domain/models/result.dart';
import '../settings/settings_view_model.dart';

/// Onboarding steps, in order (FR-1).
enum OnboardingStep { login, mainPlaylist, homePlaylists, palette }

/// State of the onboarding flow. Choices are saved only on [finish].
class OnboardingViewModel extends ChangeNotifier {
  OnboardingViewModel({
    required this._auth,
    required this._playlists,
    required this._settings,
  });

  final AuthRepository _auth;
  final PlaylistRepository _playlists;
  final SettingsViewModel _settings;

  OnboardingStep _step = OnboardingStep.login;
  bool _busy = false;
  String? _errorMessage;
  List<PlaylistSummary> _playlistOptions = const [];
  String? _mainPlaylistId;
  HomePlaylistsOption _homePlaylistsOption = HomePlaylistsOption.appOnly;
  late Palette _palette = _settings.palette;

  OnboardingStep get step => _step;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  List<PlaylistSummary> get playlistOptions => _playlistOptions;
  String? get mainPlaylistId => _mainPlaylistId;
  HomePlaylistsOption get homePlaylistsOption => _homePlaylistsOption;
  Palette get palette => _palette;

  /// No going back to login once logged in.
  bool get canGoBack => _step.index > OnboardingStep.mainPlaylist.index;

  bool get canGoNext => switch (_step) {
        OnboardingStep.login => false,
        OnboardingStep.mainPlaylist => _mainPlaylistId != null,
        OnboardingStep.homePlaylists || OnboardingStep.palette => true,
      };

  /// Skips the login step if a session already exists.
  void init() {
    if (_auth.isLoggedIn.value) {
      _step = OnboardingStep.mainPlaylist;
      loadPlaylists();
    }
  }

  Future<void> login() async {
    _setBusy(true);
    final result = await _auth.login();
    switch (result) {
      case Ok():
        _step = OnboardingStep.mainPlaylist;
        _setBusy(false);
        await loadPlaylists();
      case Error():
        _errorMessage = 'Login failed. Please try again.';
        _setBusy(false);
    }
  }

  Future<void> loadPlaylists() async {
    _setBusy(true);
    final result = await _playlists.getOwnedSpotifyPlaylists();
    switch (result) {
      case Ok(:final value):
        _playlistOptions = value;
        if (value.isEmpty) {
          _errorMessage = 'You have no playlists of your own. '
              'Create one in Spotify and retry.';
        }
      case Error():
        _errorMessage = 'Could not load your playlists.';
    }
    _setBusy(false);
  }

  void selectMainPlaylist(String id) {
    _mainPlaylistId = id;
    notifyListeners();
  }

  void selectHomePlaylistsOption(HomePlaylistsOption option) {
    _homePlaylistsOption = option;
    notifyListeners();
  }

  /// Applies the palette right away so the user sees it (FR-15.6).
  void selectPalette(Palette palette) {
    _palette = palette;
    _settings.previewPalette(palette);
    notifyListeners();
  }

  void back() {
    if (!canGoBack) return;
    _step = OnboardingStep.values[_step.index - 1];
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> next() async {
    if (!canGoNext) return;
    if (_step == OnboardingStep.palette) return finish();
    _step = OnboardingStep.values[_step.index + 1];
    _errorMessage = null;
    notifyListeners();
  }

  /// Saves the choices; the router then redirects to Home.
  Future<void> finish() async {
    final mainPlaylistId = _mainPlaylistId;
    if (mainPlaylistId == null) return;
    _setBusy(true);
    try {
      await _settings.completeOnboarding(
        mainPlaylistId: mainPlaylistId,
        homePlaylistsOption: _homePlaylistsOption,
        palette: _palette,
      );
    } on Exception {
      _errorMessage = 'Could not save your choices.';
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    if (value) _errorMessage = null;
    notifyListeners();
  }
}