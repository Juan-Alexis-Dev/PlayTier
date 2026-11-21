import 'package:flutter/material.dart';

import '../../domain/models/palette.dart';
import 'app_colors.dart';

/// Builds the app's dark [ThemeData] from a [Palette] (FR-15.3).
class AppTheme {
  const AppTheme._();

  static ThemeData fromPalette(Palette palette) {
    final surface = palette.surface;
    final background = palette.background;
    final highlight = palette.lyricsHighlight;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: Color(palette.seed),
      brightness: Brightness.dark,
      surface: surface == null ? null : Color(surface),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          background == null ? colorScheme.surface : Color(background),
      extensions: [
        AppColors(
          lyricsHighlight:
              highlight == null ? colorScheme.primary : Color(highlight),
        ),
      ],
    );
  }
}