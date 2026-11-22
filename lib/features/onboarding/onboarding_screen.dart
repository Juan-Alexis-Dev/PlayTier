import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/theme/preset_palettes.dart';
import '../../domain/models/home_playlists_option.dart';
import 'onboarding_view_model.dart';

/// Login → main playlist → Home playlists option → palette (FR-1).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OnboardingViewModel>();
    final theme = Theme.of(context);
    final error = vm.errorMessage;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Step ${vm.step.index + 1} of '
                    '${OnboardingStep.values.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: switch (vm.step) {
                      OnboardingStep.login => _LoginStep(vm),
                      OnboardingStep.mainPlaylist => _MainPlaylistStep(vm),
                      OnboardingStep.homePlaylists => _HomePlaylistsStep(vm),
                      OnboardingStep.palette => _PaletteStep(vm),
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (vm.step != OnboardingStep.login) ...[
                    const SizedBox(height: 16),
                    _NavigationButtons(vm),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: textTheme.bodyMedium),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _LoginStep extends StatelessWidget {
  const _LoginStep(this.vm);

  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.queue_music, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Welcome to PlayTier', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Log in with your Spotify Premium account to start.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: vm.busy ? null : vm.login,
          icon: const Icon(Icons.login),
          label: const Text('Log in with Spotify'),
        ),
        if (vm.busy) ...[
          const SizedBox(height: 16),
          const Text('Finish the login in your browser…'),
        ],
      ],
    );
  }
}

class _MainPlaylistStep extends StatelessWidget {
  const _MainPlaylistStep(this.vm);

  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final playlists = vm.playlistOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          'Choose your main playlist',
          'The Spotify playlist that holds all your music.',
        ),
        Expanded(
          child: vm.busy && playlists.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : playlists.isEmpty
                  ? Center(
                      child: OutlinedButton.icon(
                        onPressed: vm.loadPlaylists,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final selected = playlist.id == vm.mainPlaylistId;
                        return ListTile(
                          leading: _Cover(playlist.coverUrl),
                          title: Text(playlist.name),
                          subtitle: Text('${playlist.trackCount} tracks'),
                          selected: selected,
                          trailing: selected
                              ? const Icon(Icons.check_circle)
                              : null,
                          onTap: () => vm.selectMainPlaylist(playlist.id),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover(this.url);

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note),
    );
    final coverUrl = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.square(
        dimension: 48,
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

class _HomePlaylistsStep extends StatelessWidget {
  const _HomePlaylistsStep(this.vm);

  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    Widget option(HomePlaylistsOption value, String title, String subtitle) {
      final selected = vm.homePlaylistsOption == value;
      return ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        selected: selected,
        trailing: selected
            ? const Icon(Icons.check_circle)
            : const Icon(Icons.circle_outlined),
        onTap: () => vm.selectHomePlaylistsOption(value),
      );
    }

    return ListView(
      children: [
        const _StepHeader(
          'What should Home show?',
          'Under "Your playlists". You can change it later in Settings.',
        ),
        option(
          HomePlaylistsOption.appOnly,
          'Only PlayTier playlists',
          'Playlists you create with this app.',
        ),
        option(
          HomePlaylistsOption.includeSpotify,
          'Also my Spotify playlists',
          'Your other Spotify playlists too.',
        ),
      ],
    );
  }
}

class _PaletteStep extends StatelessWidget {
  const _PaletteStep(this.vm);

  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        const _StepHeader(
          'Pick a color palette',
          'The app changes color right away. You can change it later.',
        ),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            for (final palette in PresetPalettes.all)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => vm.selectPalette(palette),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Color(palette.seed),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette == vm.palette
                                ? colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(palette.name),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NavigationButtons extends StatelessWidget {
  const _NavigationButtons(this.vm);

  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final isLast = vm.step == OnboardingStep.palette;
    return Row(
      children: [
        if (vm.canGoBack)
          TextButton(
            onPressed: vm.busy ? null : vm.back,
            child: const Text('Back'),
          ),
        const Spacer(),
        FilledButton(
          onPressed: vm.canGoNext && !vm.busy ? vm.next : null,
          child: Text(isLast ? 'Finish' : 'Next'),
        ),
      ],
    );
  }
}