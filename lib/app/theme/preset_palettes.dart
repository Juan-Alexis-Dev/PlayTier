import '../../domain/models/palette.dart';

/// Built-in dark palettes (FR-15.2). Green is the default.
class PresetPalettes {
  const PresetPalettes._();

  static const green = Palette(name: 'Green', seed: 0xFF12C66B);
  static const purple = Palette(name: 'Purple', seed: 0xFF8B3DFF);
  static const blue = Palette(name: 'Blue', seed: 0xFF2F7BFF);
  static const amber = Palette(name: 'Amber', seed: 0xFFF5A524);
  static const coral = Palette(name: 'Coral', seed: 0xFFFF5C5C);

  /// Palette used on first launch and when the saved one is missing.
  static const defaultPalette = purple;

  /// All presets, in the order shown in Settings.
  static const all = [green, purple, blue, amber, coral];

  /// Returns the preset named [name], or [defaultPalette] if none matches.
  static Palette byName(String name) {
    for (final palette in all) {
      if (palette.name == name) return palette;
    }
    return defaultPalette;
  }
}