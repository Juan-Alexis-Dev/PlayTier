/// Error during Spotify login or token refresh.
class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message, {this.code});

  final String message;

  /// OAuth error code from Spotify (e.g. `invalid_grant`), if any.
  final String? code;

  /// True when the refresh token was revoked or expired: the user must
  /// log in again.
  bool get isInvalidGrant => code == 'invalid_grant';

  @override
  String toString() => 'SpotifyAuthException($message)';
}