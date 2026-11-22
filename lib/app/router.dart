import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../features/browse/browse_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/onboarding_view_model.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/playlist/playlist_view_model.dart';
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
  static const search = '/search';
  static const genres = '/genres';
  static const artists = '/artists';
  static const settings = '/settings';
}

/// Builds the app's [GoRouter].
///
/// With [auth] and [settings], every route except onboarding requires a
/// session and finished onboarding. Without them (widget tests of the
/// shell) there is no redirect.
GoRouter createRouter({
  AuthRepository? auth,
  SettingsViewModel? settings,
}) {
  return GoRouter(
    initialLocation: AppRoutes.home,
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
              builder: (context, state) => const HomeScreen(),
              routes: [
                // Inside the Home branch so the tabs stay visible.
                GoRoute(
                  path: 'main',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) =>
                        PlaylistViewModel(library: context.read())..init(),
                    child: const PlaylistScreen(),
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