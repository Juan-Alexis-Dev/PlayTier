import 'package:material_ui/material_ui.dart';

import '../../../domain/models/track.dart';
import '../../../shared/widgets/cover_image.dart';

/// One row of the track list: cover, name, artists and duration.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.artists,
    this.onTap,
  });

  final Track track;

  /// Artist names already joined ("A, B").
  final String artists;
  final VoidCallback? onTap;

  static String _formatDuration(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CoverImage(track.coverUrl),
      title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(_formatDuration(track.duration)),
      onTap: onTap,
    );
  }
}