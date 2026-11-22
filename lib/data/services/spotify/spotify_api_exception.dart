/// Non-success response from the Spotify Web API.
class SpotifyApiException implements Exception {
  const SpotifyApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'SpotifyApiException($statusCode, $message)';
}