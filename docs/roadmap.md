# Music Program — Roadmap

> Step-by-step plan from zero to v1.0. Companion to [`requirements.md`](requirements.md) and [`architecture.md`](architecture.md).
> Last updated: 2026-11-26

## How to use this plan

- Work milestone by milestone, in order. Each milestone ends with a **Definition of done**.
- Each numbered step becomes a **GitHub issue**; each milestone becomes a **GitHub milestone**.
- One branch per issue (`feat/weighted-shuffle`), merged into `main` through a pull request with CI green.
- Tag a release at the end of every milestone (`v0.1.0`, `v0.2.0`, …).

---

## Phase 0 — Preparation

**Goal:** accounts, tools and an empty, well-configured repository.

1. **Spotify developer app**
   - Create an app in the Spotify Developer Dashboard (your account must have Premium).
   - Add redirect URIs: a loopback URI for desktop (e.g. `http://127.0.0.1:43821/callback`) and a custom scheme for Android (e.g. `musicprogram://callback`).
   - Add your own account as an authorized user.
2. **Last.fm API key** — create an API account and save the key.
3. **Development environment**
   - Flutter SDK (stable) on your machine; run `flutter doctor`.
   - Linux desktop build dependencies; Android SDK + a physical device with the Spotify app.
   - Windows: Visual Studio Build Tools (on a Windows machine or VM) for later testing.
4. **Repository**
   - Create `music_program` on GitHub (Juan-Alexis-Dev). Choose a license (MIT recommended).
   - `flutter create` with platforms `android,linux,windows`.
   - Add `.gitignore` entries for `config.json`.
   - Copy `docs/requirements.md`, `docs/architecture.md`, `docs/roadmap.md` into the repo.
   - First README: one-paragraph description, "work in progress" badge, links to the docs.
5. **Project management**
   - GitHub Project board (To do / In progress / Done).
   - Create milestones v0.0 → v1.0 and the issues listed below.
6. **CI**
   - `.github/workflows/ci.yaml` running `flutter analyze` and `flutter test`.
   - `analysis_options.yaml` with `flutter_lints`.

**Definition of done:** the empty app builds on Linux and Android; CI passes; board and issues exist.

---

## v0.0a — Technical spike: login + playback

**Goal:** prove the riskiest part works on all 3 platforms before building anything else. Code lives in a throwaway branch `spike/playback`.

1. PKCE login on Linux with a loopback redirect; print the access token.
2. Same login on Android with the custom scheme.
3. Read the main playlist (`GET /playlists/{id}/items`) and print 20 tracks.
4. Desktop: list devices and start playback of a playlist URI on the Spotify desktop app.
5. Android: connect `spotify_sdk` App Remote and play the same playlist; read player state.
6. Create a private playlist, write 150 track URIs in chunks, and play it in order with shuffle off.
7. Repeat steps 1, 3 and 4 on Windows.
8. Write down findings in `docs/spikes/playback.md` (what worked, package versions, problems).

**Definition of done:** login + read + play works on Linux, Android and Windows, or the blockers are documented with a workaround.

## v0.0b — Lyrics spike (go/no-go)

1. `tool/lyrics_coverage.dart`: reads the main playlist, queries LRCLIB per track, reports % with synced lyrics.
2. Minimal screen in the spike branch: shows lyrics and highlights the current line using the player position (Android push, desktop polling + timer).
3. Decide: **≥ 70 % synced and highlight in sync → GO**, otherwise drop FR-13. Record the result in the decision log of `requirements.md`.

**Definition of done:** documented GO/NO-GO.

---

## v0.1 — Foundation

**Goal:** real app skeleton with login, onboarding, sync and a playlist screen.

1. Create the folder structure from `architecture.md` (empty files where needed).
2. `domain/result.dart` and the base models (`Track`, `Artist`, `PlaylistSummary`, `Palette`).
3. `app/config.dart` with `--dart-define-from-file`; `config.example.json`.
4. Theme system: `preset_palettes.dart`, `app_theme.dart` (dark `ColorScheme.fromSeed`); default green.
5. `router.dart` + `adaptive_shell.dart`: 5 tabs, bottom bar on phone, navigation rail on desktop; placeholder screens.
6. drift database: tables from the architecture; first migration.
7. `SpotifyAuthService`, `SpotifyHttpClient` (auth, refresh, 429 backoff), `SecureStorageService`, `AuthRepository`.
8. Onboarding: login → choose main playlist → Home playlists option → palette.
9. `SpotifyApiService` (playlist + items + artists) and `LibraryRepository.syncIfChanged()` with `snapshot_id`.
10. `PlaylistScreen` showing the main playlist from the DB (header, track list, action row with disabled buttons).
11. Home screen: Main and Liked cards, "Your playlists" grid.
12. Tests: models, sync logic with mocked service.

**Definition of done:** a fresh install logs in, syncs the main playlist and shows it; re-opening the app only re-syncs if the playlist changed.

---

## v0.2 — Filters, sorting and playlist creation

1. `FilterCriteria`, `SortOption` models.
2. `FilterEngine` + tests (OR within type, AND across types).
3. `SortEngine` + tests.
4. `FacetCounter` + tests (values ordered by frequency).
5. `PlaybackService` interface + both implementations (from the spike) + `PlaybackRepository.playList()`.
6. `PlaylistRepository`: playback playlist write, create permanent playlist.
7. Filter sheet + Sort menu in `PlaylistScreen`.
8. `PlaylistNameGenerator` + tests.
9. Preview screen: name, cover mosaic, removable tracks, Temporary / Permanent.
10. Permanent playlists appear in Home.

**Definition of done:** the user filters by several criteria, sorts, previews and creates a temporary or permanent playlist that plays in Spotify.

---

## v0.3 — Like levels, weighted shuffle and player

1. `LikeLevel` model + `LevelsRepository` (default 1, delete on removal).
2. `WeightedShuffle` + extensive tests (copies = level, ≥1 gap, spacing, short lists, seeded random).
3. `PlaybackRepository.playShuffled()` + round regeneration.
4. Shuffle button in `PlaylistScreen`.
5. `PlayerViewModel` (app-wide) + `MiniPlayer` in the shell.
6. Now Playing screen: context, track, cover with Spotify link, controls, `LevelStars`.
7. Disabled stars + "Add to main playlist" for tracks not in the main playlist.
8. Liked page: levels 2–5, level filter bar.
9. Set the level from track lists without playing (long press / "More options" → level sheet) + "★N" badge next to the duration (FR-3.3, FR-3.4).
10. Device selector (play on PC from phone).
11. Test v0.3 on Android, Linux and Windows.

**Definition of done:** levels can be set from Now Playing and from any track list; shuffle respects levels and spacing; Liked page filters by level; mini-player works on phone and desktop.

---

## v0.4 — Genres and Artists

1. `LastFmService` (artist tags) and `MusicBrainzService`.
2. `GenreRepository.enrichMissing()` (Spotify → Last.fm → MusicBrainz), cached.
3. Browse screen (shared) with search bar and symmetric grid (name, count, cover mosaic).
4. Genres tab and Artists tab using the Browse screen.
5. Opening a card → `PlaylistScreen` for that virtual playlist ("Add music" hidden).
6. Verify that adding/removing a track in Spotify updates the virtual playlists after sync.

**Definition of done:** every track appears under its genres and artists; tracks without Spotify genres get them from Last.fm/MusicBrainz.

---

## v0.5 — Search and adding music

1. `SearchRepository` (Spotify search, "already in main" flag).
2. Search bar in Search & Discover; result list with "Add" button.
3. "Add music" in permanent playlists (adds to the playlist and to main).
4. Sync after adding; new track shows level 1 and appears in its virtual playlists.

**Definition of done:** a searched track can be added and immediately appears in the main playlist, its genre and artist playlists.

---

## v0.6 — Discover

1. `LastFmService`: top tracks (artist/tag), similar artists/tracks/tags, charts.
2. `DiscoverRepository` + Last.fm → Spotify matching + exclusion of owned tracks (tests with mocks).
3. Mode 1: New music from your artists.
4. Mode 2: New music from your genres.
5. Mode 3: Music you could like.
6. Mode 4: Music to try (outside your taste).
7. Own parameters: autocomplete chips input → modes 1/2 with chosen values.
8. All modes end in the Preview screen; Permanent creates only the playlist.

**Definition of done:** each card returns a reasonable list of tracks the user does not have, and it can be played or saved.

---

## v0.7 — About, lyrics and palette import

1. About sheet (Last.fm track/artist info, fallback metadata).
2. *(If GO in v0.0b)* `LrcParser` + `LyricsSync` + tests, `LyricsRepository`, Lyrics screen with highlight and auto-scroll, LRCLIB credit, Settings toggle.
3. `PaletteValidator` + tests; import/export palette JSON in Settings.
4. Settings screen complete: account, main playlist, Home option, manual sync, palettes, lyrics, attributions.

**Definition of done:** all requirements in `requirements.md` are implemented (or explicitly dropped).

---

## v1.0 — Polish and release

1. Bug-fix pass on Android, Linux and Windows.
2. Error and empty states everywhere (no device, no network, 429, empty playlist).
3. Performance check: filters/shuffle < 200 ms with 2,000 tracks.
4. Accessibility pass: text sizes, contrast, tooltips on icon buttons.
5. App name, logo and icons (Q-3).
6. README final: description, screenshots/GIFs, features, architecture summary, setup guide (Spotify app, redirect URIs, Premium, 5-user limit, Last.fm key, `config.json`), attributions, license.
7. Build artifacts: Android APK, Linux bundle (tar.gz or AppImage), Windows zip.
8. GitHub Release `v1.0.0` with artifacts and changelog.
9. Pin the repository on your GitHub profile and add it to LinkedIn/CV.

**Definition of done:** a public release that another Premium user can install and configure by following the README.

---

## After v1.0 (ideas, not committed)

- Cross-device sync of levels (export/import or backend).
- Riverpod migration.
- Word-level lyric highlight.
- Statistics page (top genres/artists of the main playlist).
