import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playtier/data/services/spotify/spotify_http_client.dart';

void main() {
  final uri = Uri.parse('https://api.spotify.com/v1/me');

  test('adds the bearer token', () async {
    String? auth;
    final client = SpotifyHttpClient(
      getAccessToken: () async => 'token1',
      refreshAccessToken: () async => null,
      inner: MockClient((request) async {
        auth = request.headers['Authorization'];
        return http.Response('{}', 200);
      }),
    );

    await client.get(uri);

    expect(auth, 'Bearer token1');
  });

  test('on 401 refreshes once and retries with the new token', () async {
    final tokensSent = <String?>[];
    var refreshCalls = 0;
    final client = SpotifyHttpClient(
      getAccessToken: () async => 'old',
      refreshAccessToken: () async {
        refreshCalls++;
        return 'new';
      },
      inner: MockClient((request) async {
        tokensSent.add(request.headers['Authorization']);
        return tokensSent.length == 1
            ? http.Response('', 401)
            : http.Response('{}', 200);
      }),
    );

    final response = await client.get(uri);

    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
    expect(tokensSent, ['Bearer old', 'Bearer new']);
  });

  test('on 401 returns the response if refresh fails', () async {
    final client = SpotifyHttpClient(
      getAccessToken: () async => 'old',
      refreshAccessToken: () async => null,
      inner: MockClient((request) async => http.Response('', 401)),
    );

    final response = await client.get(uri);

    expect(response.statusCode, 401);
  });

  test('on 429 waits Retry-After and retries', () async {
    final waits = <Duration>[];
    var calls = 0;
    final client = SpotifyHttpClient(
      getAccessToken: () async => 't',
      refreshAccessToken: () async => null,
      delay: (d) async => waits.add(d),
      inner: MockClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('', 429, headers: {'retry-after': '2'})
            : http.Response('{}', 200);
      }),
    );

    final response = await client.get(uri);

    expect(response.statusCode, 200);
    expect(waits, [const Duration(seconds: 2)]);
  });

  test('on 429 gives up after maxRetries', () async {
    var calls = 0;
    final client = SpotifyHttpClient(
      getAccessToken: () async => 't',
      refreshAccessToken: () async => null,
      maxRetries: 2,
      delay: (_) async {},
      inner: MockClient((request) async {
        calls++;
        return http.Response('', 429);
      }),
    );

    final response = await client.get(uri);

    expect(response.statusCode, 429);
    expect(calls, 3); // 1 try + 2 retries
  });
}