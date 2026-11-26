/// Error response from the Last.fm API.
///
/// [errorCode] is Last.fm's own code when the body had one
/// (e.g. 10 = invalid API key, 29 = rate limit exceeded).
class LastFmApiException implements Exception {
  const LastFmApiException(this.statusCode, this.message, {this.errorCode});

  final int statusCode;
  final String message;
  final int? errorCode;

  @override
  String toString() =>
      'LastFmApiException($statusCode, error: $errorCode, $message)';
}