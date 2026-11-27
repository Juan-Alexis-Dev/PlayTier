import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/library_repository.dart';
import '../domain/models/playlist_draft.dart';
import '../features/home/home_view_model.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/browse_view_model.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/onboarding_view_model.dart';
import '../features/player/now_playing_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/playlist/playlist_view_model.dart';
import '../features/preview/preview_screen.dart';
import '../features/preview/preview_view_model.dart';
import '../features/search_discover/search_discover_screen.dart';
import '../features/search_discover/search_view_model.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/settings_view_model.dart';
import 'shell/adaptive_shell.dart';

/// Route paths, so screens never hard-code them.
class AppRoutes {
  const AppRoutes._();

  static const onboarding = '/onboarding';
  static const home = '/home';
  static const mainPlaylist = '/home/main';

  /// Main tracks with level 2–5 (FR-7).
  static const liked = '/home/liked';

  /// Needs a `PlaylistDraft` as `extra`.
  static const preview = '/home/preview';

  ///A permanent playlist or one of the user's own Spotify playlists.
  static String playlist(String id) => '/home/playlist/$id';
  static const search = '/search';
  static const genres = '/genres';

  /// Genre virtual playlist. The genre goes in the query: names can have
  /// spaces, accents or "/".
  static String genrePlaylist(String genre) =>
      Uri(path: '$genres/playlist', queryParameters: {'genre': genre})
          .toString();

  static const artists = '/artists';

  /// Artist virtual playlist (Spotify artist id).
  static String artistPlaylist(String artistId) => '$artists/$artistId';
  static const settings = '/settings';

  /// Full screen, above the tabs (opened from the mini-player).
  static const nowPlaying = '/now-playing';
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
      GoRoute(
        path: AppRoutes.nowPlaying,
        builder: (context, state) => const NowPlayingScreen(),
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
                  genres: context.read(),
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
                  path: 'liked',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) => PlaylistViewModel(
                      isLiked: true,
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
              builder: (context, state) => ChangeNotifierProvider(
                create: (context) => SearchViewModel(
                  search: context.read(),
                  library: context.read(),
                ),
                child: const SearchDiscoverScreen(),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.genres,
              builder: (context, state) => ChangeNotifierProvider(
                create: (context) => BrowseViewModel(
                  context.read<LibraryRepository>().watchGenrePlaylists(),
                )..init(),
                child: BrowseScreen(
                  kind: BrowseKind.genres,
                  onOpen: (item) =>
                      context.go(AppRoutes.genrePlaylist(item.id)),
                ),
              ),
              routes: [
                // Inside the Genres branch so the tabs stay visible.
                GoRoute(
                  path: 'playlist',
                  redirect: (context, state) =>
                      state.uri.queryParameters['genre'] == null
                          ? AppRoutes.genres
                          : null,
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) => PlaylistViewModel(
                      genre: state.uri.queryParameters['genre'],
                      library: context.read(),
                      levels: context.read(),
                      playback: context.read(),
                      playlists: context.read(),
                      settings: context.read(),
                    )..init(),
                    child: const PlaylistScreen(),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.artists,
              builder: (context, state) => ChangeNotifierProvider(
                create: (context) => BrowseViewModel(
                  context.read<LibraryRepository>().watchArtistPlaylists(),
                )..init(),
                child: BrowseScreen(
                  kind: BrowseKind.artists,
                  onOpen: (item) =>
                      context.go(AppRoutes.artistPlaylist(item.id)),
                ),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (context) => PlaylistViewModel(
                      artistId: state.pathParameters['id'],
                      library: context.read(),
                      levels: context.read(),
                      playback: context.read(),
                      playlists: context.read(),
                      settings: context.read(),
                    )..init(),
                    child: const PlaylistScreen(),
                  ),
                ),
              ],
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