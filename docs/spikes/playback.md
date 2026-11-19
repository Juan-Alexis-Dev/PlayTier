# Spike v0.0a — Login + playback

> Technical spike to prove the riskiest part of PlayTier (Spotify login, reading the main playlist and controlling playback) on Android, Linux and Windows before building the real app.
> All the branch was centered in proving that the app could be made, like a test.
> Code: branch `spike/playback` (`lib/main.dart`, throwaway). Companion to [`../requirements.md`](../requirements.md), [`../architecture.md`](../architecture.md) and [`../roadmap.md`](../roadmap.md).
> Date: November 2026.

## 1. Summary

| Step | Linux | Android | Windows |
|---|---|---|---|
| 1–2. PKCE login |loopback server | custom scheme + `app_links` | loopback server (same code as Linux) |
| 3. Read main playlist (paginated) | works | works |works |
| 4. List devices + play on a Connect device (Web API) | works | works (phone and PC appear as devices) | works |
| 5. App Remote: play + push player state | — | works with workarounds | — |
| 6. Private playback playlist, written in chunks of 100, played in order | works | works | works |

**Conclusion:** login, reading and playback work on the three platforms. The Web API alone can control every platform (including the phone). App Remote works on Android but needs three workarounds; it is only required for push player state (lyrics sync).

## 2. Environment and package versions

| Tool | Version |
|---|---|
| Flutter | 3.47.2 (stable) — also pinned in CI |
| Dart SDK constraint | `^3.13.2` |
| Android Gradle Plugin | 9.1.0 |
| Kotlin Gradle plugin | 2.4.0 |
| Gradle | 9.3.1 |
| Test devices | Linux laptop (ASUS TUF F16) · Android: Honor `MTN-NX3` · Windows PC (Visual Studio 2022, same Flutter version) |

| Package | Version | Used for |
|---|---|---|
| `http` | 1.6.0 | Web API calls |
| `crypto` | 3.0.8 | PKCE `code_challenge` (SHA-256) |
| `url_launcher` | 6.3.3 | Opening the Spotify login page |
| `app_links` | 7.2.2 | Receiving `playtier://callback` on Android |
| `spotify_sdk` (+ `spotify_sdk_android`) | 4.3.4 | App Remote on Android (needs Flutter ≥ 3.47.1) |
| `flutter_lints` | 6.0.0 | Lints |

## 3. Spotify Developer Dashboard configuration

- **APIs used:** Web API, Android.
- **Redirect URIs:**
  - `http://127.0.0.1:43821/callback` — desktop login (Linux, Windows).
  - `playtier://callback` — Android login (Web API).
  - `playtier://app-remote` — App Remote authorization (Android).
- **Android package:** `com.juanalexisdev.playtier` + SHA-1 of the signing certificate (debug keystore for now; the release keystore must be added before v1.0).
- **User Management:** every account that uses the app must be added while the app is in Development Mode.
- **Account:** Spotify Premium is required for every playback endpoint.

`config.json` (git-ignored) holds `SPOTIFY_CLIENT_ID`, the three redirect URIs and `SPOTIFY_MAIN_PLAYLIST_ID`, passed with `--dart-define-from-file=config.json`.

## 4. What worked (per step)

### 4.1 Login (PKCE, no client secret)

- Scopes: `playlist-read-private`, `playlist-read-collaborative`, `playlist-modify-private`, `playlist-modify-public`, `user-read-playback-state`, `user-modify-playback-state`.
- **Desktop:** `HttpServer` bound to `127.0.0.1:43821` receives the redirect, the browser shows "login complete", the code is exchanged at `POST /api/token`.
- **Android:** the browser redirects to `playtier://callback`; `app_links` delivers it to `MainActivity` (`launchMode="singleTop"`). Listen to `uriLinkStream` **before** opening the browser so the redirect is not missed.
- The same PKCE code (verifier, challenge, state check, token exchange) is shared; only "how the code is received" differs per platform.

### 4.2 Read the main playlist

- `GET /playlists/{id}/items?limit=50&market=from_token&fields=next,total,items(added_at,is_local,item(type,id,name,uri,is_playable,artists(name)))`
- Follow `next` until `null` (2 requests for ~100 tracks).
- Use `items[].item` — `items[].track` is a deprecated alias. `/playlists/{id}/tracks` endpoints are deprecated → use `/items`.
- Skip `item == null` (unavailable) and `type == "episode"`. Mark `is_local` and `is_playable == false`.
- Only works for playlists the user owns or collaborates on (`403` otherwise).

### 4.3 Devices and playback (Web API, all platforms)

- `GET /me/player/devices` → `id`, `name`, `type` (`Computer`, `Smartphone`…), `is_active`, `is_restricted`.
- `PUT /me/player/play?device_id=…` with `{context_uri, offset: {position}}` → `204`.
- `PUT /me/player` with `{device_ids: [id], play: false}` moves playback to a device without starting it.
- The desktop app only appears while it is open; the phone appears while the Spotify app is alive.

### 4.4 App Remote (Android only)

- `SpotifySdk.getAccessToken(scope: 'app-remote-control')` (first time only) → `connectToSpotifyRemote()` → `switchToLocalDevice()` → `play()`.
- `subscribePlayerState()` pushes `PlayerState` (`track`, `isPaused`, `playbackPosition`, `playbackOptions.isShuffling`) on track change, play/pause and seek.

### 4.5 Playback playlist (in order)

- Find `PlayTier — Playback` in `GET /me/playlists` (paged, max 50); create it once with `POST /me/playlists` `{name, public: false}` and reuse it, so the library is not filled with temporary playlists.
- Write in chunks of 100: first chunk `PUT /playlists/{id}/items` (**replaces** all items), the rest `POST /playlists/{id}/items` (**appends** in order). The last chunk only carries the remaining tracks.
- Play with `offset.position = 0`, then `PUT /me/player/shuffle?state=false`.
- Verified with `POST /me/player/next` + `GET /me/player`: every checked track matched the written order and `shuffle_state` was `false`.
- Duplicated URIs are allowed in a playlist (needed for weighted shuffle: copies = level).

## 5. Problems and workarounds


### 5.1 Android

| Problem | Workaround |
|---|---|
| Flutter's own deep-link handling intercepts `playtier://callback`. | `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />` in `MainActivity`. |
| `keytool` crashes with `MissingFormatArgumentException` on a Spanish locale. | `keytool -J-Duser.language=en …`, or `./gradlew signingReport`. |
| `RedirectUriReceiverActivity` and `MainActivity` would both claim the same redirect. | Separate redirect URIs: `playtier://callback` (login) and `playtier://app-remote` (App Remote), distinct hosts. |
| `connectToSpotifyRemote()` failed with `UserNotAuthorizedException`, later a timeout. Logcat: `Background activity launch blocked!` — the Spotify app tries to open its consent screen from the background and Android blocks it. | Authorize first with `SpotifySdk.getAccessToken(scope: 'app-remote-control')`, which opens the consent screen from PlayTier while it is in the foreground. Only needed once per install. |
| `play()` started music on the PC: App Remote sends commands to the **active Connect device**, not necessarily the phone. | Call `SpotifySdk.switchToLocalDevice()` before `play()`. |
| Authorization/connection hung while another device (PC) was the active Connect device. | Transfer playback to the phone first (`PUT /me/player`, `play: false`). On Android the phone is the default device. |
| Honor (Magic OS) freezes Spotify in the background (`AppFastHibernation … F_Z`); App Remote then never answers. | Open Spotify once before connecting. User setting: App launch → Spotify → manage manually (auto-launch, secondary launch, run in background). Document in the README. |
| `PlayerState.playbackPosition` is only pushed on events, not every second. | Interpolate locally: last position + time since the event (if not paused). |
| `connectToSpotifyRemote()` can wait forever. | Always use a timeout (30 s; 90 s for the authorization screen). |

### 5.2 Linux

- No platform-specific problems. Spotify desktop app must be open to appear as a device.

### 5.3 Windows

Once the toolchain was installed, login, reading, Connect playback and the playback playlist worked with no code changes.

| Problem | Workaround |
|---|---|
| Windows apps can't be built from Linux: the first setup requires installing the whole toolchain on Windows. | Build on a Windows machine with Visual Studio 2022 ("Desktop development with C++") and the same Flutter version. |
| `Building with plugins requires symlink support`. | Enable Windows Developer Mode. |

End users do **not** need Flutter: release builds are distributed as a zip (`build\windows\x64\runner\Release\`). The Visual C++ runtime DLLs should be bundled or linked in the README.