import 'package:material_ui/material_ui.dart';

import 'cover_image.dart';

/// Square cover made from track covers: a 2×2 grid with 4 or more URLs,
/// otherwise the first cover (or the placeholder when there is none).
class CoverMosaic extends StatelessWidget {
  const CoverMosaic(
    this.urls, {
    super.key,
    this.size = 160,
    this.borderRadius = 8,
  });

  final List<String> urls;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (urls.length < 4) {
      return CoverImage(
        urls.firstOrNull,
        size: size,
        borderRadius: borderRadius,
      );
    }
    final half = size / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              Row(
                children: [
                  for (var col = 0; col < 2; col++)
                    CoverImage(urls[row * 2 + col], size: half, borderRadius: 0),
                ],
              ),
          ],
        ),
      ),
    );
  }
}