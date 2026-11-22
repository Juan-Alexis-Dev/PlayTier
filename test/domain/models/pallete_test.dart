import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/app/theme/preset_palettes.dart';
import 'package:playtier/domain/models/palette.dart';

void main() {
  test('equality includes overrides', () {
    const a = Palette(name: 'X', seed: 0xFF000000);
    const b = Palette(name: 'X', seed: 0xFF000000, surface: 0xFF111111);

    expect(a, const Palette(name: 'X', seed: 0xFF000000));
    expect(a, isNot(b));
    expect(a.copyWith(surface: 0xFF111111), b);
  });

  group('PresetPalettes', () {
    test('green is the default and first', () {
      expect(PresetPalettes.defaultPalette, PresetPalettes.green);
      expect(PresetPalettes.all.first, PresetPalettes.green);
      expect(PresetPalettes.all, hasLength(5));
    });

    test('byName finds a preset or falls back to the default', () {
      expect(PresetPalettes.byName('Coral'), PresetPalettes.coral);
      expect(PresetPalettes.byName('Missing'), PresetPalettes.defaultPalette);
    });

    test('preset names are unique', () {
      final names = PresetPalettes.all.map((p) => p.name).toSet();
      expect(names, hasLength(PresetPalettes.all.length));
    });
  });
}