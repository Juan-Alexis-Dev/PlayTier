import 'package:material_ui/material_ui.dart';

/// Square cover from a URL, with a placeholder when missing or broken.
class CoverImage extends StatelessWidget {
  const CoverImage(
    this.url, {
    super.key,
    this.size = 48,
    this.borderRadius = 4,
  });

  final String? url;

  /// Side length. Use `double.infinity` to fill the parent.
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        // `size` may be infinite when the parent sets the size.
        size: size.isFinite ? size * 0.5 : 48,
        color: colorScheme.onSurfaceVariant,
      ),
    );
    final coverUrl = url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: coverUrl == null
            ? placeholder
            : Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}