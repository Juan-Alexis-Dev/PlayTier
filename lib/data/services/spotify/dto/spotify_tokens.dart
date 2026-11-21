/// Access and refresh tokens returned by Spotify's `/api/token`.
class SpotifyTokens {
  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Parses a token response. Refresh responses may omit `refresh_token`;
  /// then [previousRefreshToken] is kept.
  factory SpotifyTokens.fromTokenResponse(
    Map<String, dynamic> json, {
    String? previousRefreshToken,
    DateTime? now,
  }) {
    final refreshToken =
        json['refresh_token'] as String? ?? previousRefreshToken;
    if (refreshToken == null) {
      throw const FormatException('Token response without refresh_token');
    }
    return SpotifyTokens(
      accessToken: json['access_token'] as String,
      refreshToken: refreshToken,
      expiresAt: (now ?? DateTime.now())
          .add(Duration(seconds: json['expires_in'] as int)),
    );
  }

  /// Reads tokens saved with [toJson].
  factory SpotifyTokens.fromJson(Map<String, dynamic> json) {
    return SpotifyTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// True if the access token expires within the next minute.
  bool isExpired([DateTime? now]) => !(now ?? DateTime.now())
      .isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };
}