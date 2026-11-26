/// Non-success response from the MusicBrainz API (503 = rate limited).
class MusicBrainzApiException implements Exception {
  const MusicBrainzApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'MusicBrainzApiException($statusCode, $message)';
}