/// A dark color palette (FR-15).
///
/// Colors are stored as ARGB integers (e.g. `0xFF12C66B`) so the domain
/// stays free of Flutter imports. `app_theme.dart` converts them with
/// `Color(value)` and builds the scheme with `ColorScheme.fromSeed`.
class Palette {
  const Palette({
    required this.name,
    required this.seed,
    this.background,
    this.surface,
    this.lyricsHighlight,
  });

  /// Display name, also used as the palette key.
  final String name;
  /// Seed color for `ColorScheme.fromSeed` (dark).
  final int seed;
  /// Optional override for the scaffold background.
  final int? background;
  /// Optional override for the surface color.
  final int? surface;
  /// Optional color for the current lyric line.
  final int? lyricsHighlight;

  Palette copyWith({
    String? name,
    int? seed,
    int? background,
    int? surface,
    int? lyricsHighlight,
  }) {
    return Palette(
      name: name ?? this.name,
      seed: seed ?? this.seed,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      lyricsHighlight: lyricsHighlight ?? this.lyricsHighlight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Palette &&
          other.name == name &&
          other.seed == seed &&
          other.background == background &&
          other.surface == surface &&
          other.lyricsHighlight == lyricsHighlight;

  @override
  int get hashCode =>
      Object.hash(name, seed, background, surface, lyricsHighlight);

  @override
  String toString() => 'Palette($name)';
}