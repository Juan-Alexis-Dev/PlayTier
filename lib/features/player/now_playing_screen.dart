import 'package:go_router/go_router.dart';
// Flutter also has a RepeatMode (animations); ours is the player's.
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../domain/models/like_level.dart';
import '../../domain/models/playback_state.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/level_stars.dart';
import '../../shared/widgets/spotify_attribution.dart';
import 'device_sheet.dart';
import 'mini_player.dart';
import 'player_view_model.dart';

/// Song view (FR-12): context, cover with a Spotify link, track, like
/// level stars and the playback controls. Uses the app-wide
/// [PlayerViewModel], so it follows whatever Spotify is playing.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  static const _maxWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlayerViewModel>();
    final state = vm.state;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.home),
        ),
        centerTitle: true,
        title: _ContextTitle(name: vm.contextName),
      ),
      body: state == null
          ? const Center(child: Text('Nothing is playing.'))
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: _Content(vm: vm, state: state),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ContextTitle extends StatelessWidget {
  const _ContextTitle({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final contextName = name;
    if (contextName == null) return const Text('Now playing');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Playing from', style: text.labelSmall),
        Text(
          contextName,
          style: text.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.vm, required this.state});

  final PlayerViewModel vm;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final spotifyUrl = Uri.https('open.spotify.com', '/track/${state.trackId}');
    final level = vm.currentLevel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: 'Open in Spotify',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => SpotifyAttribution.open(spotifyUrl),
            child: AspectRatio(
              aspectRatio: 1,
              child: CoverImage(
                state.coverUrl,
                size: double.infinity,
                borderRadius: 8,
              ),
            ),
          ),
        ),
        Center(child: SpotifyAttribution(url: spotifyUrl)),
        const SizedBox(height: 8),
        Text(
          state.trackName,
          style: text.titleLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          state.artistNames.join(', '),
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Center(
          child: LevelStars(
            level: level ?? LikeLevel.min,
            onChanged: level == null
                ? null
                : (n) => runPlayerCommand(context, () => vm.setLevel(n)),
          ),
        ),
        if (vm.canAddToMain) ...[
          Text(
            'Not in your main playlist, so it has no level yet.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: vm.addingToMain
                  ? null
                  : () => runPlayerCommand(context, vm.addToMainPlaylist),
              icon: vm.addingToMain
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add),
              label: const Text('Add to main playlist'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _ProgressBar(
          position: vm.position,
          duration: state.duration,
          onSeek: (position) =>
              runPlayerCommand(context, () => vm.seek(position)),
        ),
        _Controls(vm: vm, state: state),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => DeviceSheet.show(context, vm),
            icon: const Icon(Icons.devices),
            // Android does not report the device name.
            label: Text(state.deviceName ?? 'Choose device'),
          ),
        ),
      ],
    );
  }
}

/// Slider with elapsed and total time. Keeps the dragged value until the
/// finger is lifted, then seeks.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final max = widget.duration.inMilliseconds.toDouble();
    final safeMax = max > 0 ? max : 1.0;
    final value = (_dragging ?? widget.position.inMilliseconds.toDouble())
        .clamp(0.0, safeMax);

    return Column(
      children: [
        Slider(
          value: value,
          max: safeMax,
          onChanged: max > 0 ? (v) => setState(() => _dragging = v) : null,
          onChangeEnd: (v) {
            setState(() => _dragging = null);
            widget.onSeek(Duration(milliseconds: v.round()));
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(Duration(milliseconds: value.round())),
                style: text.bodySmall,
              ),
              Text(_format(widget.duration), style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours == 0) return '${d.inMinutes}:$seconds';
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '${d.inHours}:$minutes:$seconds';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.vm, required this.state});

  final PlayerViewModel vm;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final repeat = state.repeatMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: switch (repeat) {
            RepeatMode.off => 'Repeat: off',
            RepeatMode.context => 'Repeat: playlist',
            RepeatMode.track => 'Repeat: track',
          },
          color: repeat == RepeatMode.off ? null : colors.primary,
          onPressed: () => runPlayerCommand(context, vm.cycleRepeat),
          icon: Icon(
            repeat == RepeatMode.track ? Icons.repeat_one : Icons.repeat,
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 36,
          onPressed: () => runPlayerCommand(context, vm.previous),
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          tooltip: state.isPlaying ? 'Pause' : 'Play',
          iconSize: 40,
          onPressed: () => runPlayerCommand(context, vm.togglePlayPause),
          icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Next',
          iconSize: 36,
          onPressed: () => runPlayerCommand(context, vm.next),
          icon: const Icon(Icons.skip_next),
        ),
        // Same width as the repeat button, so play stays centered.
        const SizedBox(width: 48),
      ],
    );
  }
}