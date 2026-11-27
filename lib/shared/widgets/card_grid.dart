import 'package:material_ui/material_ui.dart';

/// Symmetric responsive grid of cards (a sliver): every cell has the same
/// size, and the number of columns grows with the available width.
///
/// Used by Home ("Your playlists") and Browse (Genres, Artists).
class CardGrid extends StatelessWidget {
  const CardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  /// Square artwork plus two lines of text below it.
  static const _delegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 200,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 0.72,
  );

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      gridDelegate: _delegate,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}