import 'package:flutter/foundation.dart';

import '../../app/theme/preset_palettes.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/home_playlists_option.dart';
import '../../domain/models/palette.dart';

/// App-wide settings state: active palette and onboarding status.
///
/// Grows into the full Settings screen state in v0.7.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._repository);

  final SettingsRepository _repository;

  Palette _palette = PresetPalettes.defaultPalette;
  bool _onboardingDone = false;

  Palette get palette => _palette;
  bool get onboardingDone => _onboardingDone;

  /// Loads saved values. Call once at startup.
  Future<void> load() async {
    final paletteName = await _repository.getPaletteName();
    _palette = paletteName == null
        ? PresetPalettes.defaultPalette
        : PresetPalettes.byName(paletteName);
    _onboardingDone = await _repository.isOnboardingDone();
    notifyListeners();
  }

  /// Applies [palette] immediately without saving it (onboarding preview).
  void previewPalette(Palette palette) {
    _palette = palette;
    notifyListeners();
  }

  /// Saves every onboarding choice and marks onboarding as done.
  Future<void> completeOnboarding({
    required String mainPlaylistId,
    required HomePlaylistsOption homePlaylistsOption,
    required Palette palette,
  }) async {
    await _repository.setMainPlaylistId(mainPlaylistId);
    await _repository.setHomePlaylistsOption(homePlaylistsOption);
    await _repository.setPaletteName(palette.name);
    await _repository.setOnboardingDone(true);
    _palette = palette;
    _onboardingDone = true;
    notifyListeners();
  }
}