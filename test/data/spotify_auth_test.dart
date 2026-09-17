import 'package:atemo_stream_player_viewer/data/spotify_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SpotifyAuth build({
    required TokenEndpoint exchange,
    DateTime Function()? now,
  }) =>
      SpotifyAuth(
        clientId: 'id',
        clientSecret: 'secret',
        refreshToken: 'refresh-0',
        exchange: exchange,
        now: now,
      );

  test('exchanges the refresh token for an access token', () async {
    final auth = build(
      exchange: (form) async {
        expect(form['grant_type'], 'refresh_token');
        expect(form['refresh_token'], 'refresh-0');
        return (status: 200, body: {'access_token': 'AT', 'expires_in': 3600});
      },
    );

    expect(await auth.accessToken(), 'AT');
  });

  test('caches the token until it nears expiry', () async {
    var calls = 0;
    var clock = DateTime(2026);
    final auth = build(
      now: () => clock,
      exchange: (_) async {
        calls++;
        return (status: 200, body: {'access_token': 'AT$calls', 'expires_in': 3600});
      },
    );

    expect(await auth.accessToken(), 'AT1');
    clock = clock.add(const Duration(minutes: 10));
    expect(await auth.accessToken(), 'AT1', reason: 'still valid, no new call');
    expect(calls, 1);

    // Past the 30s-early expiry window.
    clock = clock.add(const Duration(minutes: 51));
    expect(await auth.accessToken(), 'AT2');
    expect(calls, 2);
  });

  test('concurrent callers share one refresh', () async {
    var calls = 0;
    final auth = build(exchange: (_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return (status: 200, body: {'access_token': 'AT', 'expires_in': 3600});
    });

    await Future.wait([auth.accessToken(), auth.accessToken(), auth.accessToken()]);
    expect(calls, 1, reason: 'a burst of requests must not fire three refreshes');
  });

  test('keeps a rotated refresh token', () async {
    var seen = 'refresh-0';
    final auth = build(exchange: (form) async {
      seen = form['refresh_token']!;
      return (status: 200, body: {
        'access_token': 'AT',
        'expires_in': 1, // force the next call to refresh
        'refresh_token': 'refresh-1',
      });
    });

    await auth.accessToken();
    expect(auth.refreshToken, 'refresh-1');
    await auth.accessToken();
    expect(seen, 'refresh-1', reason: 'the rotated token is used next time');
  });

  test('a rejected refresh token is a clear, terminal error', () async {
    final auth = build(exchange: (_) async => (status: 400, body: <String, dynamic>{}));

    expect(
      () => auth.accessToken(),
      throwsA(isA<SpotifyAuthException>()
          .having((e) => e.message, 'message', contains('re-authorise'))),
    );
  });

  test('a transient failure is distinct from a dead token', () async {
    final auth = build(exchange: (_) async => (status: 503, body: <String, dynamic>{}));
    expect(
      () => auth.accessToken(),
      throwsA(isA<SpotifyAuthException>()
          .having((e) => e.message, 'message', contains('503'))),
    );
  });
}
