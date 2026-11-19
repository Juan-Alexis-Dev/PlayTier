import 'dart:io' show Platform;

/// App configuration read at compile time.
///
/// Values come from `config.json` (git-ignored) passed with:
///
/// ```bash
/// flutter run --dart-define-from-file=config.json
/// ```
///
/// See `config.example.json` for the expected keys.
class AppConfig {
  const AppConfig({
    required this.spotifyClientId,
    required this.spotifyRedirectUriDesktop,
    required this.spotifyRedirectUriAndroid,
    required this.spotifyRedirectUriAppRemote,
    required this.lastFmApiKey,
  });

  /// Reads every value from the `--dart-define` environment.
  ///
  /// Missing keys become empty strings; check [missingKeys] at startup.
  const AppConfig.fromEnvironment()
      : spotifyClientId = const String.fromEnvironment('SPOTIFY_CLIENT_ID'),
        spotifyRedirectUriDesktop =
            const String.fromEnvironment('SPOTIFY_REDIRECT_URI_DESKTOP'),
        spotifyRedirectUriAndroid =
            const String.fromEnvironment('SPOTIFY_REDIRECT_URI_ANDROID'),
        spotifyRedirectUriAppRemote =
            const String.fromEnvironment('SPOTIFY_REDIRECT_URI_APP_REMOTE'),
        lastFmApiKey = const String.fromEnvironment('LASTFM_API_KEY');

  /// Client ID of the Spotify developer app.
  final String spotifyClientId;

  /// Loopback redirect for desktop login (e.g. `http://127.0.0.1:43821/callback`).
  final String spotifyRedirectUriDesktop;

  /// Custom-scheme redirect for Android login (e.g. `playtier://callback`).
  final String spotifyRedirectUriAndroid;

  /// Redirect used by the Android App Remote SDK (e.g. `playtier://app-remote`).
  final String spotifyRedirectUriAppRemote;

  /// Last.fm API key (needed from v0.4 for genres and Discover).
  final String lastFmApiKey;

  /// Login redirect URI for the current platform.
  String get spotifyRedirectUri =>
      Platform.isAndroid ? spotifyRedirectUriAndroid : spotifyRedirectUriDesktop;

  /// True when the Last.fm key is set.
  bool get hasLastFmKey => lastFmApiKey.isNotEmpty;

  /// Names of the required keys that are empty.
  ///
  /// The Last.fm key is not required yet; use [hasLastFmKey] for it.
  List<String> get missingKeys => [
        if (spotifyClientId.isEmpty) 'SPOTIFY_CLIENT_ID',
        if (spotifyRedirectUriDesktop.isEmpty) 'SPOTIFY_REDIRECT_URI_DESKTOP',
        if (spotifyRedirectUriAndroid.isEmpty) 'SPOTIFY_REDIRECT_URI_ANDROID',
        if (spotifyRedirectUriAppRemote.isEmpty)
          'SPOTIFY_REDIRECT_URI_APP_REMOTE',
      ];

  /// True when every required key is set.
  bool get isValid => missingKeys.isEmpty;
}
