# Music Program — Architecture

> Companion to [`requirements.md`](requirements.md). Last updated: 2026-11-13

## 1. Decision

**Pattern:** MVVM (Model–View–ViewModel) with Repositories and Services, plus a pure-Dart **domain** layer.
**State management / dependency injection:** `provider` (`ChangeNotifier` ViewModels).
**Folder strategy:** feature-first for the UI, layer-first for data and domain.

## 2. Why MVVM

| Reason | Detail |
|---|---|
| Official recommendation | It is the architecture described in Flutter's official app architecture guide (Views, ViewModels, Repositories, Services), so it is easy to justify and to find documentation for. |
| Right size for a solo project | Clean Architecture adds a use-case class per action; BLoC adds events/states per screen. For one developer that is mostly boilerplate. MVVM keeps only the layers this app actually needs. |
| Separates UI from logic | Views only draw; ViewModels hold screen state; all data access goes through repositories. Changing a screen never touches API code and vice versa. |
| Testable | The core features of this app (filters, sorting, weighted shuffle, LRC parsing, palette validation) live in a pure-Dart domain layer and are unit-tested without emulator, network or Flutter. |
| Handles platform differences cleanly | Playback differs on Android vs desktop. A `PlaybackService` interface with two implementations hides that from the rest of the app. |
| Fits Provider | `ChangeNotifier` ViewModels + `Provider` is the pairing used in the official guide, and the author already knows Provider. |

**Alternatives considered:** Clean Architecture (too much boilerplate for the size), BLoC (heavier learning curve and code per screen), Riverpod (cleaner DI, but a new tool to learn; can be adopted later because the layering stays the same).

## 3. Layers

```
┌──────────────────────── UI LAYER (features/) ────────────────────────┐
│  View (Widget)  ──user action──►  ViewModel (ChangeNotifier)         │
│        ▲                               │                             │
│        └────── notifyListeners() ──────┘                             │
└────────────────────────────────────────┬─────────────────────────────┘
                                         │ calls methods / listens to streams
┌──────────────────────── DATA LAYER (data/) ──────────────────────────┐
│  Repositories  — single source of truth per data type,               │
│                  combine sources, cache, map errors to Result        │
│        │                                                             │
│  Services      — thin wrappers: one per external system              │
│                  (Spotify, Last.fm, MusicBrainz, LRCLIB, DB, storage)│
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────── DOMAIN (domain/) — pure Dart ────────────────┐
│  Models (immutable data) + Engines (pure functions)                  │
│  Used by every layer. Imports nothing from Flutter or data/.         │
└──────────────────────────────────────────────────────────────────────┘
```

### Responsibilities and rules

| Layer | Does | Never does |
|---|---|---|
| **View** | Builds widgets from ViewModel state; forwards user actions. | Business logic, HTTP, database access. |
| **ViewModel** | Holds screen state (loading, data, error); calls repositories and engines; exposes simple methods (`applyFilters()`, `shuffle()`). | Import services, parse JSON, build widgets. |
| **Repository** | Decides where data comes from (cache vs API), keeps cache in sync, merges sources (Spotify + Last.fm), retries, returns `Result<T>`. | Hold UI state, import Flutter widgets. |
| **Service** | Talks to one external system; converts JSON ↔ DTOs. | Business rules, combining sources. |
| **Domain** | Models and pure algorithms. | Any I/O, any Flutter import. |

**Dependency direction:** `features → repositories → services`. Everything may import `domain`. Nothing imports `features`.

**Errors:** repositories catch exceptions and return `Result<T>` (`Ok` / `Error`). ViewModels turn errors into UI state (message + retry). No exception crosses into a View.

**Reactive data:** repositories expose `Stream`s from drift's watch queries (e.g. tracks, levels). When sync writes to the DB, every screen listening updates automatically.

## 4. Information flows

### 4.1 Startup and sync
1. `main.dart` loads config, builds services and repositories (`app/dependencies.dart`), runs `App`.
2. Router asks `AuthRepository`: no session → Onboarding; session → Home.
3. `HomeViewModel` calls `LibraryRepository.syncIfChanged()`.
4. `LibraryRepository` → `SpotifyApiService.getPlaylist(mainId)` → compares `snapshot_id` with `sync_state`.
5. If changed → fetches items page by page → writes `tracks`, `artists`, `track_artists`; deletes removed tracks and their levels (FR-2.4); new tracks get level 1.
6. `GenreRepository.enrichMissing()` → Spotify artist genres → else Last.fm tags → else MusicBrainz → writes `artist_genres`.
7. DB streams emit → Home, Browse and Playlist ViewModels refresh.

### 4.2 Filter, sort and weighted shuffle
1. `PlaylistScreen` → user opens the filter sheet → `FilterViewModel` builds a `FilterCriteria`.
2. `PlaylistViewModel` takes tracks (`LibraryRepository`) + levels (`LevelsRepository`) → `FilterEngine.apply()` → `SortEngine.sort()` → `notifyListeners()`.
3. User taps **Shuffle** → `PlaybackRepository.playShuffled(tracks)`:
   - `WeightedShuffle.generate(tracks, levels)` builds the order (FR-4).
   - `PlaylistRepository.writePlaybackPlaylist(order)` replaces the private playback playlist (chunks ≤100).
   - `PlaybackService.playContext(playbackPlaylistUri, shuffle: false)`.
4. `PlaybackRepository` watches the player state; near the end of a round, it generates and writes the next one.

### 4.3 Setting a like level
`LevelStars` (widget) → `PlayerViewModel.setLevel(n)` → `LevelsRepository.setLevel(trackId, n)` → DB → Liked page and any open playlist update through streams.

### 4.4 Discover
1. `DiscoverViewModel.run(mode, params)` → `DiscoverRepository`.
2. Repository calls Last.fm (top tracks / similar / tags), matches each result with `SpotifyApiService.search()`, removes tracks already in the main playlist.
3. Returns a `PlaylistDraft` → router opens `PreviewScreen`.
4. `PreviewViewModel`: rename, remove tracks → **Temporary** (`PlaybackRepository.playList`) or **Permanent** (`PlaylistRepository.createPermanent`).

### 4.5 Lyrics
1. `LyricsViewModel` gets current track from `PlayerViewModel`.
2. `LyricsRepository.get(track)` → `lyrics_cache` → else `LrcLibService` → `LrcParser.parse()` → `Lyrics` (list of timed lines).
3. Listens to `PlaybackRepository.position` stream → `LyricsSync.currentLine(lines, position)` → highlights and scrolls.

### 4.6 Playback on each platform
```
PlaybackRepository ──► PlaybackService (abstract)
                           ├── AppRemotePlaybackService   (Android, spotify_sdk, push updates)
                           └── ConnectPlaybackService     (Linux/Windows, Web API, poll every few
                                                           seconds + local timer interpolation)
```
`app/dependencies.dart` picks the implementation with `Platform.isAndroid`.

## 5. Provider setup

| Scope | What | How |
|---|---|---|
| App-wide, immutable | Services and repositories | `Provider<T>` in a `MultiProvider` at the root |
| App-wide, mutable | `PlayerViewModel` (mini-player + Now Playing), `SettingsViewModel` (theme, options) | `ChangeNotifierProvider` at the root |
| Per screen | Every other ViewModel | `ChangeNotifierProvider` created by the route, disposed when the screen closes |

ViewModels receive repositories through their constructor (`context.read<LibraryRepository>()` in the route builder), so tests can pass mocks.

## 6. Folder structure and file responsibilities

```
music_program/
├── lib/
│   ├── main.dart
│   ├── app/
│   ├── domain/
│   ├── data/
│   ├── features/
│   └── shared/
├── test/
├── tool/
├── docs/
├── .github/workflows/
├── config.example.json
├── analysis_options.yaml
├── pubspec.yaml
├── README.md
└── LICENSE
```

### `lib/main.dart`
Only file directly in `lib/`. Initializes Flutter bindings, loads `AppConfig`, builds dependencies, calls `runApp(App())`.

### `lib/app/` — application wiring

| File | Responsibility |
|---|---|
| `app.dart` | Root widget: `MaterialApp.router` with the active theme from `SettingsViewModel`. |
| `router.dart` | `go_router` config: shell route with the 5 tabs (Home, Search & Discover, Genres, Artists, Settings) + routes for playlist, preview, now playing, lyrics, onboarding. Redirects to onboarding if not logged in. |
| `dependencies.dart` | Creates services and repositories, chooses the `PlaybackService` per platform, returns the provider list. |
| `config.dart` | `AppConfig`: Spotify Client ID, redirect URI, Last.fm API key, read from `--dart-define-from-file`. |
| `theme/app_theme.dart` | Builds dark `ThemeData` from a `Palette` (`ColorScheme.fromSeed` + overrides). |
| `theme/preset_palettes.dart` | The 5 built-in palettes (green, purple, blue, amber, coral). |
| `shell/adaptive_shell.dart` | Bottom navigation bar on narrow screens, `NavigationRail` on wide screens; hosts the mini-player. |

### `lib/domain/` — pure Dart

**`models/`** (immutable classes)

| File | Contents |
|---|---|
| `track.dart` | Id, URI, name, artist ids, album, duration, release date, `addedAt`, cover URL. |
| `artist.dart` | Id, name, genres. |
| `playlist_summary.dart` | Id, name, cover, track count, type (main, liked, genre, artist, permanent). |
| `like_level.dart` | Value 1–5 with validation. |
| `filter_criteria.dart` | Selected genres, artists, albums, levels, year range, date-added range. |
| `sort_option.dart` | Enum of sort fields + direction. |
| `playlist_draft.dart` | Name, image, tracks — used by the preview screen. |
| `playback_state.dart` | Current track, position, playing/paused, device, context. |
| `lyrics.dart` | `Lyrics` with a list of `LyricLine` (time, text) or plain text. |
| `palette.dart` | Name, seed, overrides. |
| `discover_mode.dart` | Enum: fromArtists, fromGenres, youCouldLike, toTry, custom. |
| `result.dart` | `Result<T>` sealed class (`Ok`, `Error`). |

**`engines/`** (pure functions, 100% unit-tested)

| File | Responsibility |
|---|---|
| `filter_engine.dart` | Applies `FilterCriteria` (OR within type, AND across types). |
| `sort_engine.dart` | Sorts by `SortOption`. |
| `facet_counter.dart` | Counts genres/artists/albums in a list, ordered by frequency (filter lists, Genres/Artists pages). |
| `weighted_shuffle.dart` | Builds a round: N copies per level, ≥1 track between copies, maximized spacing, drops impossible copies. Accepts a seeded `Random` for tests. |
| `playlist_name_generator.dart` | Provisional names from filters ("Rock + Pop · Artist X"). |
| `lrc_parser.dart` | Parses LRC text into `LyricLine`s. |
| `lyrics_sync.dart` | Finds the current line for a playback position. |
| `palette_validator.dart` | Validates imported palette JSON (hex, fields, contrast). |

### `lib/data/services/` — one per external system

| File | Responsibility |
|---|---|
| `spotify/spotify_auth_service.dart` | OAuth PKCE login, token refresh. |
| `spotify/spotify_api_service.dart` | Web API calls: playlists, items, artists, search, create playlist, player endpoints. |
| `spotify/spotify_http_client.dart` | `dio` instance with interceptors: auth header, refresh on 401, retry with backoff on 429. |
| `spotify/dto/` | JSON ↔ Dart mapping for Spotify responses. |
| `playback/playback_service.dart` | Abstract interface: play context/URIs, pause, next, previous, seek, repeat, state stream. |
| `playback/app_remote_playback_service.dart` | Android implementation (`spotify_sdk`). |
| `playback/connect_playback_service.dart` | Desktop implementation (Web API + polling + interpolation). |
| `lastfm/lastfm_service.dart` | Tags, top tracks, similar artists/tracks/tags, charts, track/artist info. |
| `musicbrainz/musicbrainz_service.dart` | Artist genre lookup (fallback). |
| `lrclib/lrclib_service.dart` | Lyrics lookup by track, artist, album, duration. |
| `local/app_database.dart` | drift database definition and migrations. |
| `local/tables.dart` | Tables: `tracks`, `artists`, `track_artists`, `artist_genres`, `track_levels`, `sync_state`, `lyrics_cache`, `palettes`, `settings`, `app_playlists`. |
| `local/secure_storage_service.dart` | Stores tokens (`flutter_secure_storage`). |
| `local/file_service.dart` | Pick/save palette JSON files. |

### `lib/data/repositories/`

| File | Responsibility |
|---|---|
| `auth_repository.dart` | Session state, login/logout. |
| `settings_repository.dart` | Main playlist id, Home option, lyrics on/off, selected palette. |
| `library_repository.dart` | Sync main playlist (snapshot), cached tracks/artists streams, add to main. |
| `genre_repository.dart` | Genre enrichment chain (Spotify → Last.fm → MusicBrainz). |
| `levels_repository.dart` | Get/set levels, stream of levels, delete on removal. |
| `playlist_repository.dart` | User/app playlists for Home, create permanent playlists, write the playback playlist. |
| `playback_repository.dart` | Wraps `PlaybackService`; play list / play shuffled; round regeneration; position stream. |
| `search_repository.dart` | Spotify search + "already in main" flag. |
| `discover_repository.dart` | The 5 discover modes; Last.fm → Spotify matching; exclusions. |
| `lyrics_repository.dart` | Cache + LRCLIB + parsing. |
| `theme_repository.dart` | Presets + imported palettes; import/export. |

### `lib/features/` — one folder per screen (View + ViewModel)

| Folder | Files | Notes |
|---|---|---|
| `onboarding/` | `onboarding_screen.dart`, `onboarding_view_model.dart` | Login → main playlist → Home option → palette. |
| `home/` | `home_screen.dart`, `home_view_model.dart` | Main + Liked cards, "Your playlists" grid. |
| `playlist/` | `playlist_screen.dart`, `playlist_view_model.dart`, `widgets/` (`playlist_header.dart`, `action_row.dart`, `track_tile.dart`, `level_filter_bar.dart`) | One screen for main, liked, genre, artist and permanent playlists. |
| `filters/` | `filter_sheet.dart`, `filter_view_model.dart` | Multi-filter panel → preview. |
| `preview/` | `preview_screen.dart`, `preview_view_model.dart` | Name, image, removable tracks, Temporary/Permanent. |
| `browse/` | `browse_screen.dart`, `browse_view_model.dart` | Genres and Artists (same screen, parameter decides content). |
| `search_discover/` | `search_discover_screen.dart`, `search_view_model.dart`, `discover_view_model.dart`, `widgets/discover_card.dart`, `widgets/parameter_chips_input.dart` | |
| `player/` | `player_view_model.dart`, `mini_player.dart`, `now_playing_screen.dart`, `about_sheet.dart` | `PlayerViewModel` is app-wide. |
| `lyrics/` | `lyrics_screen.dart`, `lyrics_view_model.dart` | Conditional feature (FR-13.0). |
| `settings/` | `settings_screen.dart`, `settings_view_model.dart`, `widgets/palette_picker.dart` | |

### `lib/shared/widgets/`
Reusable UI: `level_stars.dart`, `cover_mosaic.dart`, `card_grid.dart`, `spotify_attribution.dart`, `empty_state.dart`, `error_view.dart`, `loading_view.dart`.

### Outside `lib/`

| Path | Purpose |
|---|---|
| `test/` | Mirrors `lib/`. Priority: `domain/engines` (unit), repositories (unit with `mocktail`), a few key screens (widget tests). |
| `tool/lyrics_coverage.dart` | Spike script: % of main playlist with synced lyrics in LRCLIB (milestone v0.0b). |
| `docs/` | `requirements.md`, `architecture.md`, `roadmap.md`, screenshots. |
| `.github/workflows/ci.yaml` | `flutter analyze` + `flutter test` on every push/PR. |
| `config.example.json` | Template for secrets; real `config.json` is git-ignored. |
| `analysis_options.yaml` | Lint rules (`flutter_lints`). |

## 7. Packages

| Need | Package |
|---|---|
| State / DI | `provider` |
| Navigation | `go_router` |
| Local DB | `drift` (+ SQLite libraries for each platform) |
| HTTP | `dio` |
| OAuth | `flutter_web_auth_2` (+ PKCE helper) |
| Token storage | `flutter_secure_storage` |
| Android playback | `spotify_sdk` |
| Files | `file_picker` |
| Tests | `flutter_test`, `mocktail` |
| Lints | `flutter_lints` |

Exact versions and Linux/Windows compatibility are confirmed during the v0.0a spike.

## 8. Conventions

- File names `snake_case.dart`; one public class per file.
- ViewModels end in `ViewModel`, repositories in `Repository`, services in `Service`.
- No hard-coded colors or strings in widgets; colors from the theme.
- Domain classes are immutable (`final` fields, `copyWith`).
- Every engine has a test file before it is used by a ViewModel.
- Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
