import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/cover_mosaic.dart';
import '../playlist/widgets/track_tile.dart';
import 'preview_view_model.dart';

/// Preview before creating a playlist (FR-8.1): editable name, cover
/// mosaic, removable tracks, and Temporary / Permanent (FR-8.2).
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: context.read<PreviewViewModel>().name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _formatTotal(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return hours > 0 ? '$hours h $minutes min' : '$minutes min';
  }

  Future<void> _run(Future<void> Function() action) async {
    final vm = context.read<PreviewViewModel>();
    await action();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = vm.errorMessage;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final text = switch (vm.outcome) {
      PreviewOutcome.played => 'Playing "${vm.nameToSave}" in Spotify.',
      PreviewOutcome.saved => 'Saved "${vm.nameToSave}" to your Spotify.',
      null => null,
    };
    if (text == null) return;
    messenger.showSnackBar(SnackBar(content: Text(text)));
    context.pop();
  }

  void _remove(PreviewViewModel vm, int index) {
    final track = vm.removeAt(index);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "${track.name}".'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => vm.undoRemove(index, track),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PreviewViewModel>();
    final draft = vm.draft;
    final tracks = draft.tracks;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New playlist')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CoverMosaic(draft.coverUrls),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TextField(
                      controller: _nameController,
                      enabled: !vm.busy,
                      maxLength: 100,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        counterText: '',
                      ),
                      onChanged: vm.rename,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${tracks.length} tracks · '
                    '${_formatTotal(draft.totalDuration)}',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No tracks left.')),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) => TrackTile(
                track: tracks[index],
                artists: vm.artistsOf(tracks[index]),
                onRemove: vm.busy ? null : () => _remove(vm, index),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Temporary'),
                  onPressed:
                      vm.canFinish ? () => _run(vm.playTemporary) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: vm.busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.library_add),
                  label: const Text('Permanent'),
                  onPressed:
                      vm.canFinish ? () => _run(vm.savePermanent) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}