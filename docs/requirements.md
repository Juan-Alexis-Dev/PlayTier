# Music Program — Requirements (v0.4 draft)

> Working name. Final name and logo pending (author's own design).
> Last updated: 2026-11-26

## 1. Overview

Music Program is a cross-platform companion app for Spotify, built with Flutter (Android, Linux, Windows). It targets people who keep **all their music in a single Spotify playlist** and want to filter, group and shuffle it quickly without manually maintaining many playlists.

The app does **not** play audio itself. It reads the user's library through the Spotify Web API, computes filters, virtual playlists and a weighted shuffle locally, and tells the official Spotify app what to play.

## 2. Constraints

| # | Constraint | Source / reason |
|---|---|---|
| C-1 | The app owner and every user need **Spotify Premium**. | Spotify Development Mode + playback control |
| C-2 | Development Mode allows **max 5 authorized users per app**. Each person who clones the repo registers their own Client ID. | Spotify Web API (Feb 2026 changes) |
| C-3 | The official **Spotify app must be installed and running** on the device that plays audio (desktop app on Linux/Windows, Spotify app on Android). | App Remote SDK / Spotify Connect |
| C-4 | **No audio download or storage.** Ever. | Spotify Developer Terms |
| C-5 | Spotify metadata and cover art may only be **cached temporarily** for performance; the cache is re-synced, never used as a backup. | Spotify Developer Policy |
| C-6 | Spotify content must be **attributed** (Spotify logo/icon) and **link back** to Spotify. Titles are shown unmodified. | Spotify Design & Branding Guidelines |
| C-7 | No mixing with **streams from other services** (e.g. YouTube). External services may provide metadata only. | Spotify Developer Policy |
| C-8 | Removed Spotify endpoints (recommendations, related artists, audio features, artist top tracks, batch fetches, `popularity` field) must not be relied on. Spotify provides **no lyrics** through its API. | Spotify Web API changes (Nov 2024, Feb 2026) |
| C-9 | API quota is limited and shared per developer account → minimize calls, cache aggressively, handle `429` with retry/backoff. Avoid high-frequency polling. | Spotify Web API (Jul 2026 quota update) |
| C-10 | App name, logo and default theme must not imply an official Spotify product (e.g. do not copy Spotify's exact green + black look). | Spotify Branding Guidelines |
| C-11 | Lyrics are copyrighted. Free synced lyrics come from a community source (LRCLIB), not a licensed provider → lyrics feature is for personal, non-commercial use, with attribution, and can be disabled. | Lyrics licensing |

## 3. Glossary

- **Main playlist** — A regular Spotify playlist owned by the user that holds all their music. Single source of truth.
- **"Adding" a song** — Adding it to the main playlist (replaces the idea of "downloading").
- **Like level** — Integer 1–5 stored by the app per track, on each device. Default 1.
- **Virtual playlist** — A list computed inside the app (by genre, artist, filters). Not created in Spotify.
- **Subplaylist** — Any playlist derived from the main playlist: virtual (genre/artist) or created by the user from filters.
- **Temporary playlist** — Played through the playback playlist; nothing permanent is saved.
- **Permanent playlist** — A real playlist created in the user's Spotify account.
- **Playback playlist** — A private Spotify playlist owned by the app where the computed play order is written so Spotify plays it in order.
- **Theme palette** — A named dark color set (seed color + optional overrides) that styles the whole app.

## 4. Functional requirements

### FR-1 Authentication & onboarding
- FR-1.1 Log in with Spotify using OAuth 2.0 Authorization Code + PKCE (no client secret in the app).
- FR-1.2 On first run, the user selects which of their playlists is the main playlist.
- FR-1.3 On first run, the user chooses what Home shows under "Your playlists": **only playlists created with the app**, or **also their other Spotify playlists**.
- FR-1.4 On first run, the user picks a theme palette (FR-15).
- FR-1.5 All onboarding choices can be changed later in Settings.
- FR-1.6 The app creates (or reuses) its private playback playlist.

### FR-2 Library sync
- FR-2.1 Sync the main playlist into a local cache: track, artists, album, duration, release date, `added_at`, cover URL.
- FR-2.2 Detect changes using the playlist `snapshot_id`; only re-sync when it changes.
- FR-2.3 A new track in the main playlist (added from this app or from Spotify) gets like level 1 and is automatically placed in the matching virtual playlists.
- FR-2.4 A track removed from the main playlist disappears from all virtual playlists and its like level is deleted. Permanent playlists already created in Spotify are not modified.
- FR-2.5 Genre enrichment: use Spotify artist genres first; if empty, use Last.fm artist top tags; MusicBrainz as fallback.

### FR-3 Like levels
- FR-3.1 Every track in the main playlist has a level from 1 to 5 (default 1). Shown as 5 stars/hearts; UI to raise/lower it.
- FR-3.2 Levels are stored **locally on each device**. They are **not synced** between devices.
- FR-3.3 The level can be set **without playing the track**: long press on a track in any track list (or its "More options" button on desktop) opens a sheet with cover, title and the 5 stars. Tracks not in the main playlist show the stars disabled (same rule as FR-12.4).
- FR-3.4 Track lists show a small "★N" badge next to the duration for tracks with level 2–5.

### FR-4 Weighted shuffle
- FR-4.1 Applies to any list: main playlist, virtual playlist, filter result, Liked page.
- FR-4.2 Each track appears **as many times as its level** in one shuffle round (level 3 → 3 times).
- FR-4.3 Copies of the same track must have **at least 1 different track between them**; the algorithm maximizes the distance between copies.
- FR-4.4 If the constraint cannot be met (e.g. very short list), extra copies that would violate it are dropped.
- FR-4.5 When a round ends, a new round with a new order is generated and playback continues.
- FR-4.6 The order is written to the playback playlist (in chunks of ≤100 items) and played in order with Spotify's own shuffle off. If the app is closed, Spotify keeps playing that playlist (and repeats it with repeat mode on); when the app is open it regenerates the next round.
- FR-4.7 Example: A, B, C, D (level 1), E (level 2), F (level 3) → 9 plays, e.g. `F B E D F A C E F`.

### FR-5 Filters & sorting
- FR-5.1 Filter types: genre, artist, album, like level, release year, date added.
- FR-5.2 Multiple filters can be active at once. Same type → **OR** (Rock OR Pop). Different types → **AND** ((Rock OR Pop) AND artist X).
- FR-5.3 Filter value lists are ordered by frequency in the current list (most common genre/artist first).
- FR-5.4 Sort options, applied to the filtered result: date added (newest/oldest), title, artist, album, duration, like level.
- FR-5.5 A filtered result can be played (temporary) or saved (permanent) via FR-8.

### FR-6 Virtual playlists
- FR-6.1 **Genres page:** one virtual playlist per genre present in the main playlist. A track with several genres appears in several playlists.
- FR-6.2 **Artists page:** one virtual playlist per artist present in the main playlist (featured artists included).
- FR-6.3 Virtual playlists update automatically after each sync. Nothing is created in Spotify.

### FR-7 Liked page
- FR-7.1 Shows tracks with level 2–5, each **once**.
- FR-7.2 Has a level filter (only on this page): checkboxes 2, 3, 4, 5; all active by default. It only shows/hides tracks.
- FR-7.3 Shuffle from this page uses FR-4 weights.

### FR-8 Playlist creation with preview
- FR-8.1 Before creating any playlist (from filters or Discover), show a preview with:
  - provisional name (generated from the active filters, editable),
  - image (cover mosaic of the first tracks),
  - track list where any track can be removed.
- FR-8.2 Choose **Temporary** (plays via the playback playlist, nothing saved) or **Permanent** (creates a real playlist in Spotify).

### FR-9 Search & adding music
- FR-9.1 Spotify search by track, artist or album.
- FR-9.2 Results show whether the track is already in the main playlist.
- FR-9.3 "Add" from Search = add to the main playlist; it then flows through FR-2.3.
- FR-9.4 "Add music" inside a **permanent playlist** adds the track to that playlist **and** to the main playlist (if missing).
- FR-9.5 "Add music" is **hidden** in genre and artist virtual playlists.

### FR-10 Discover
- FR-10.1 **New music from your artists:** tracks from the user's artists that are not in the main playlist, ranked with Last.fm `artist.getTopTracks`.
- FR-10.2 **New music from your genres:** first, tracks of the user's top genres from artists already in the main playlist that the user doesn't have; then the most popular tracks of those genres (Last.fm `tag.getTopTracks`) from any artist.
- FR-10.3 **Music you could like** (inside your taste): tracks from artists and genres similar to the ones the user listens to (Last.fm `artist.getSimilar`, `track.getSimilar`, `tag.getSimilar`).
- FR-10.4 **Music to try** (outside your taste): popular genres, artists and tracks that are **different** from the user's library — e.g. Last.fm top tags/charts excluding the user's genres and artists.
- FR-10.5 **Own parameters:** input with autocomplete where the user picks artists and/or genres as chips, then runs FR-10.1 / FR-10.2 with them.
- FR-10.6 Last.fm results are matched to Spotify tracks via Spotify search. Tracks already in the main playlist are excluded.
- FR-10.7 Results always go through the preview (FR-8). **Permanent → only a new playlist is created in Spotify; the tracks are NOT added to the main playlist.** The user can add individual tracks to the main playlist afterwards (e.g. from Now Playing, FR-12.4).

### FR-11 Playback control
- FR-11.1 Play/pause, next, previous, seek, repeat, current track display.
- FR-11.2 Select target device (e.g. control the PC from the phone).
- FR-11.3 Android: Spotify App Remote SDK (push updates of player state). Linux/Windows: Web API player endpoints (Spotify Connect).
- FR-11.4 On desktop, playback position is obtained by polling the player every few seconds and interpolated locally with a timer; re-synced on track change, seek or pause.
- FR-11.5 Clear message when no active Spotify device is found.

### FR-12 Now Playing (song view)
- FR-12.1 Top: context playlist name, track name and artist.
- FR-12.2 Center: cover art (links to the track in Spotify, with Spotify attribution).
- FR-12.3 Bottom: standard controls (FR-11) plus **5 stars/hearts** to set the like level. Tapping star N sets level N; minimum is 1.
- FR-12.4 If the playing track is not in the main playlist (e.g. a Discover playlist), the stars are disabled and an "Add to main playlist" button is shown.
- FR-12.5 Buttons: **Lyrics** (FR-13) and **About** (FR-14).

### FR-13 Lyrics view — conditional
- FR-13.0 **Go/no-go:** this feature is built only if the lyrics spike (milestone v0.0b) passes: LRCLIB must have synced lyrics for **≥ 70%** of the author's main playlist and line highlighting must stay in sync on both Android and desktop. Otherwise the feature is dropped and the Lyrics button is removed.
- FR-13.1 Replaces the song view. Top: playlist name, track name, artist and a back button to the song view.
- FR-13.2 Rest of the screen: lyrics only.
- FR-13.3 Synced lyrics: the current line is highlighted with the theme's highlight color and auto-scrolled into view, following the playback position (FR-11.4). Word-level highlight only if the source provides it.
- FR-13.4 Fallback: plain lyrics without highlight; if none, a "No lyrics available" message.
- FR-13.5 Source: LRCLIB (free, no API key), queried by track name, artist, album and duration. Lyrics cached locally. LRCLIB is credited in the view.

### FR-14 About view
- FR-14.1 Modal/sheet with the track and artist description from Last.fm (`track.getInfo` wiki, `artist.getInfo` bio), plus genres and like level.
- FR-14.2 If nothing is available, show basic metadata (album, release date, duration).

### FR-15 Themes and color palettes
- FR-15.1 All palettes are **dark mode**. No light mode.
- FR-15.2 Preloaded palettes (seed colors):

  | Palette | Seed |
  |---|---|
  | Green (default) | `#12C66B` |
  | Purple | `#8B3DFF` |
  | Blue | `#2F7BFF` |
  | Amber | `#F5A524` |
  | Coral | `#FF5C5C` |

- FR-15.3 Each palette is defined by a **seed color** plus optional overrides; the full dark color scheme is generated from the seed (Material 3 `ColorScheme.fromSeed`, `Brightness.dark`).
- FR-15.4 The user can **import** a palette from a JSON file and **export** any palette to share it.
- FR-15.5 Imported palettes are validated (valid hex colors, required fields, minimum text contrast) before being applied; invalid files show an error.
- FR-15.6 Palette selection applies immediately and persists across launches.

Palette file format (draft):

```json
{
  "name": "Emerald Night",
  "version": 1,
  "seed": "#12C66B",
  "overrides": {
    "background": "#0E1210",
    "surface": "#17201B",
    "lyricsHighlight": "#7CFFB2"
  }
}
```

## 5. Screens and navigation

Navigation: bottom bar on phones, side navigation rail on desktop (Linux/Windows), same 5 destinations. A **mini-player** bar sits above the bottom bar (phones) or at the bottom of the window (desktop) and opens the song view.

| # | Screen | Content |
|---|---|---|
| 1 | **Home** | Two large cards: Main playlist and Liked playlist. Below: "Your playlists" grid (content depends on FR-1.3). |
| 2 | **Search & Discover** | Search bar on top. Text: "Want new music? Try these:". "Own parameters" input (FR-10.5). Four cards in a 2×2 grid: New music from your artists / from your genres / you could like / to try. |
| 3 | **Genres** | Search bar to find a genre. Symmetric grid of genre cards (name, track count, cover mosaic), ordered by track count. |
| 4 | **Artists** | Same layout as Genres, with artist content. |
| 5 | **Settings** | Generic settings page: account, main playlist, Home playlists option, sync (manual sync, last sync time), theme palettes (select/import/export), lyrics on/off, about the app and attributions. |

Shared screens:

- **Playlist view** (Spotify-like layout). Header: cover, name, track count. Action row: **Play**, **Shuffle** (weighted), **Sort**, **New subplaylist** (opens filter panel → preview FR-8), **Add music** (FR-9.4/9.5), **More options**. Then the track list (level badge FR-3.4; long press / "More options" per track → level sheet FR-3.3).
- **Playlist preview** (FR-8).
- **Now Playing** (FR-12), **Lyrics** (FR-13), **About** (FR-14).

Layout must be symmetric and responsive.

## 6. Non-functional requirements

- NFR-1 Platforms: Android, Linux, Windows.
- NFR-2 Filtering, sorting and shuffle run locally; results in < 200 ms for a 2,000-track library.
- NFR-3 Minimize API calls: incremental sync, per-artist caching, retry with backoff on `429`, no sub-second polling.
- NFR-4 Core logic (filters, sort, weighted shuffle, name generator, LRC parser, palette validation) is pure Dart and covered by unit tests.
- NFR-5 No secrets in the repository; Client ID and Last.fm API key loaded from local config.
- NFR-6 README documents setup: Spotify Developer app, redirect URIs, Premium requirement, 5-user limit, Last.fm key, data source attributions, palette file format.
- NFR-7 Responsive layout: phone (bottom navigation) and desktop (navigation rail).
- NFR-8 All colors come from the active theme; no hard-coded colors in widgets.

## 7. External data sources

| Source | Used for | Auth |
|---|---|---|
| Spotify Web API | Library, search, playlists, playback (desktop) | OAuth PKCE |
| Spotify App Remote SDK | Playback (Android) | Spotify app login |
| Last.fm API | Genres (tags), popularity, similar artists/tracks/tags, charts, descriptions | API key |
| MusicBrainz API | Genre fallback | None (User-Agent required) |
| LRCLIB | Synced and plain lyrics (conditional, FR-13.0) | None |

## 8. Out of scope

- Playing or downloading audio inside the app.
- Audio features (tempo, energy, danceability).
- Any non-Spotify streaming source (YouTube, local files).
- Podcasts and audiobooks.
- iOS, macOS, web.
- Commercial distribution / Extended Quota Mode.
- Licensed lyrics providers (e.g. paid Musixmatch plans).
- Visual theme editor inside the app (palettes are imported as files).
- Light mode.
- Cross-device sync of like levels (no backend).

## 9. Milestones

| Version | Scope |
|---|---|
| v0.0a | Technical spike: login + playback control on Linux, Windows and Android |
| v0.0b | Lyrics spike: LRCLIB coverage over the main playlist + line sync test → go/no-go for FR-13 |
| v0.1 | Auth, onboarding, sync + local cache, navigation shell, theme system with presets, playlist view |
| v0.2 | Filters + sorting + preview + temporary/permanent playlists |
| v0.3 | Like levels (Now Playing and track lists) + weighted shuffle + Liked page + Now Playing view + mini-player |
| v0.4 | Genres and Artists pages (virtual playlists) + genre enrichment |
| v0.5 | Search + add music |
| v0.6 | Discover |
| v0.7 | About view + lyrics (if v0.0b passed) + palette import/export |

## 10. Open questions

- **Q-3** Final app name and logo.

## 11. Decision log

| Date | Decision |
|---|---|
| 2026-11-12 | App is a Spotify controller; no audio download/playback in-app. |
| 2026-11-12 | Main playlist is a regular Spotify playlist. |
| 2026-11-12 | Genre/artist playlists are virtual (in-app only). |
| 2026-11-12 | Filters: OR within same type, AND across types. |
| 2026-11-12 | Like levels stored in the app; Liked page shows levels 2–5 once, with level filter. |
| 2026-11-12 | Weighted shuffle via private playback playlist. |
| 2026-11-12 | External data: Last.fm (primary), MusicBrainz (fallback). YouTube idea discarded. |
| 2026-11-13 | Mini-player + navigation rail on desktop; Shuffle button in playlist view. |
| 2026-11-13 | "Own parameters" uses autocomplete chips. |
| 2026-11-13 | "Music you could like" = inside taste; "Music to try" = outside taste. |
| 2026-11-13 | "Add music" in permanent playlists also adds to main; hidden in virtual playlists. |
| 2026-11-13 | Home playlists option asked during onboarding. |
| 2026-11-13 | Settings is the 5th tab (generic settings page). |
| 2026-11-13 | Lyrics are conditional on a coverage/sync spike (≥ 70% synced). |
| 2026-11-13 | Multiple preloaded dark palettes (green default, purple, blue, amber, coral) + JSON import/export. |
| 2026-11-13 | Like levels are device-local; no cross-device sync, no backend. |
| 2026-11-13 | Discover → Permanent creates a playlist only; tracks are not added to the main playlist. |
| 2026-11-26 | Levels can also be set from track lists without playing (long press / "More options" → level sheet), and lists show a "★N" badge for levels 2–5 (FR-3.3, FR-3.4). Added to v0.3 as issue 9; device selector moves to issue 10. |
