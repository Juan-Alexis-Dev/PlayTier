import 'package:flutter/material.dart';

/// Play, Shuffle, Sort, New subplaylist, Add music, More options.
///
/// Every callback is optional: a null callback shows a disabled button.
/// They are wired in v0.2 (play, sort, subplaylist) and v0.3 (shuffle).
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    this.onPlay,
    this.onShuffle,
    this.onSort,
    this.onNewSubplaylist,
    this.onAddMusic,
    this.onMore,
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback? onSort;
  final VoidCallback? onNewSubplaylist;
  final VoidCallback? onAddMusic;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
          FilledButton.tonalIcon(
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle),
            label: const Text('Shuffle'),
          ),
          IconButton(
            onPressed: onSort,
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
          ),
          IconButton(
            onPressed: onNewSubplaylist,
            tooltip: 'New subplaylist',
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            onPressed: onAddMusic,
            tooltip: 'Add music',
            icon: const Icon(Icons.playlist_add),
          ),
          IconButton(
            onPressed: onMore,
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }
}