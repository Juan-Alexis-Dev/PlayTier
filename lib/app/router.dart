import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../domain/models/playlist_draft.dart';
import '../features/home/home_view_model.dart';
import '../features/browse/browse_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/onboarding_view_model.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/playlist/playlist_view_model.dart';
import '../features/preview/preview_screen.dart';
import '../features/preview/preview_view_model.dart';
import '../features/search_discover/search_discover_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/settings_view_model.dart';
import 'shell/adaptive_shell.dart';

/// Route paths, so screens never hard-code them.
class AppRoutes {
  const AppRoutes._();

  static const onboarding = '/onboarding';
  static const home = '/home';
  static const mainPlaylist = '/home/main';

  /// Needs a `PlaylistDraft` as `extra`.
  static const preview = '/home/preview';

  ///A permanent playlist or one of the user's own Spotify playlists.
  static String playlist(String id) => '/home/playlist/$id';
  static const search = '/search';
  static const genres = '/genres';
  static const artists = '/artists';
  static const settings = '/settings';
}

/// Builds the app's [GoRouter].
///
/// With [auth] and [settings], every route except onboarding requires a
/// session and finished onboarding. Without them (widget tests of the
/// shell) there is no redirect. Tests can also pick [initialLocation].
GoRouter createRouter({
  AuthRepository? auth,
  SettingsViewModel? settings,
  String initialLocation = AppRoutes.home,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: auth == null || settings == null
        ? null
        : Listenable.merge([auth.isLoggedIn, settings]),
    redirect: (context, state) {
      if (auth == null || settings == null) return null;
      final ready = auth.isLoggedIn.value && settings.onboardingDone;
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!ready) return atOnboarding ? null : AppRoutes.onboarding;
      return atOnboarding ? AppRoutes.home : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => ChangeNotifierProvider(
          create: (context) => OnboardingViewModel(
            auth: context.read(),
            playlists: context.read(),
            settings: context.read(),
          )..init(),
          child: const OnboardingScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => ChangeNotifierProvider(
                create: (context) => HomeViewModel(
                  library: context.read(),
                  levels: context.read(),
                  playlists: context.read(),
                  settings: context.read(),
                )..init(),
                child: const HomeScreen(),
              ),
              routes: [
                // Inside the Home branch so the tabs stay visible.
                GoRoute(
                  path: 'main',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) => PlaylistViewModel(
                      library: context.read(),
                      levels: context.read(),
                      playback: context.read(),
                      playlists: context.read(),
                      settings: context.read(),
                    )..init(),
                    child: const PlaylistScreen(),
                  ),
                ),
                GoRoute(
                  path: 'playlist/:id',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) => PlaylistViewModel(
                      playlistId: state.pathParameters['id'],
                      library: context.read(),
                      levels: context.read(),
                      playback: context.read(),
                      playlists: context.read(),
                      settings: context.read(),
                    )..init(),
                    child: const PlaylistScreen(),
                  ),
                ),
                GoRoute(
                  path: 'preview',
                  // No draft (e.g. a restored route): back to Home.
                  redirect: (context, state) =>
                      state.extra is PlaylistDraft ? null : AppRoutes.home,
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) => PreviewViewModel(
                      draft: state.extra! as PlaylistDraft,
                      library: context.read(),
                      playback: context.read(),
                      playlists: context.read(),
                    )..init(),
                    child: const PreviewScreen(),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.search,
              builder: (context, state) => const SearchDiscoverScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.genres,
              builder: (context, state) =>
                  const BrowseScreen(kind: BrowseKind.genres),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.artists,
              builder: (context, state) =>
                  const BrowseScreen(kind: BrowseKind.artists),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
}