import 'package:go_router/go_router.dart';

import '../features/browse/browse_screen.dart';
import '../features/home/home_screen.dart';
import '../features/search_discover/search_discover_screen.dart';
import '../features/settings/settings_screen.dart';
import 'shell/adaptive_shell.dart';

/// Route paths, so screens never hard-code them.
class AppRoutes {
  const AppRoutes._();

  static const home = '/home';
  static const search = '/search';
  static const genres = '/genres';
  static const artists = '/artists';
  static const settings = '/settings';
}

/// Builds the app's [GoRouter].
/// One branch per tab; `StatefulShellRoute.indexedStack` keeps each tab's
/// state when switching. Playlist, preview, now playing, lyrics and
/// onboarding routes are added in later steps.
GoRouter createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
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