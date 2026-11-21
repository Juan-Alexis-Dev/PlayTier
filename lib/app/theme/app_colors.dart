import 'package:flutter/material.dart';

/// ```dart
/// final colors = Theme.of(context).extension<AppColors>()!;
/// ```
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.lyricsHighlight});

  /// Color of the current lyric line (FR-13.3).
  final Color lyricsHighlight;

  @override
  AppColors copyWith({Color? lyricsHighlight}) {
    return AppColors(lyricsHighlight: lyricsHighlight ?? this.lyricsHighlight);
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      lyricsHighlight: Color.lerp(lyricsHighlight, other.lyricsHighlight, t)!,
    );
  }
}