import 'package:flutter_test/flutter_test.dart';
import 'package:playtier/data/services/spotify/dto/spotify_tokens.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);

  test('fromTokenResponse computes the expiry time', () {
    final tokens = SpotifyTokens.fromTokenResponse(
      {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600},
      now: now,
    );

    expect(tokens.accessToken, 'a');
    expect(tokens.refreshToken, 'r');
    expect(tokens.expiresAt, DateTime(2026, 1, 1, 13));
  });

  test('a refresh response without refresh_token keeps the previous one', () {
    final tokens = SpotifyTokens.fromTokenResponse(
      {'access_token': 'a2', 'expires_in': 3600},
      previousRefreshToken: 'r1',
      now: now,
    );

    expect(tokens.refreshToken, 'r1');
  });

  test('a response without any refresh token throws', () {
    expect(
      () => SpotifyTokens.fromTokenResponse(
        {'access_token': 'a', 'expires_in': 3600},
      ),
      throwsFormatException,
    );
  });

  test('isExpired one minute before the real expiry', () {
    final tokens = SpotifyTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: now.add(const Duration(minutes: 5)),
    );

    expect(tokens.isExpired(now), isFalse);
    expect(tokens.isExpired(now.add(const Duration(minutes: 4))), isTrue);
  });

  test('toJson and fromJson round-trip', () {
    final tokens = SpotifyTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: now,
    );
    final copy = SpotifyTokens.fromJson(tokens.toJson());

    expect(copy.accessToken, 'a');
    expect(copy.refreshToken, 'r');
    expect(copy.expiresAt, now);
  });
}