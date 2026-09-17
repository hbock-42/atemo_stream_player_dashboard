/// Spotify OAuth token management for the relay.
///
/// The Authorization Code flow gives a long-lived refresh token once (after the
/// user authorises the app in a browser); from then on this exchanges it for
/// short-lived access tokens as they expire. All of it runs server-side on the
/// relay — the client secret and refresh token never reach a browser
/// (ADR-0005).
///
/// The HTTP exchange is injected, so the refresh-and-cache logic is tested
/// without a network or a real Spotify app.
library;

import 'dart:convert';

/// One call to Spotify's token endpoint. Returns the decoded JSON body and the
/// status, so the caller can tell an expired refresh token (400/401) from a
/// transient failure.
typedef TokenEndpoint = Future<({int status, Map<String, dynamic> body})> Function(
  Map<String, String> form,
);

class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message);
  final String message;
  @override
  String toString() => 'SpotifyAuthException: $message';
}

class SpotifyAuth {
  SpotifyAuth({
    required this.clientId,
    required this.clientSecret,
    required String refreshToken,
    required this.exchange,
    DateTime Function()? now,
  })  : _refreshToken = refreshToken,
        _now = now ?? DateTime.now;

  final String clientId;
  final String clientSecret;
  final TokenEndpoint exchange;
  final DateTime Function() _now;

  String _refreshToken;
  String? _accessToken;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The Basic auth header for the token endpoint.
  String get basicAuth =>
      'Basic ${base64.encode(utf8.encode('$clientId:$clientSecret'))}';

  /// A valid access token, refreshing if the cached one is within 30s of
  /// expiry. Concurrent callers share one in-flight refresh.
  Future<String> accessToken() async {
    final cached = _accessToken;
    if (cached != null && _now().isBefore(_expiresAt)) return cached;
    return _refresh();
  }

  Future<String>? _inFlight;

  Future<String> _refresh() {
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  Future<String> _doRefresh() async {
    final result = await exchange({
      'grant_type': 'refresh_token',
      'refresh_token': _refreshToken,
    });

    if (result.status == 400 || result.status == 401) {
      // The refresh token is dead — revoked, or the app's secret changed. Only
      // re-authorising in a browser fixes this; say so rather than retrying.
      throw const SpotifyAuthException(
        'Spotify refresh token rejected — re-authorise (see docs/spotify.md)',
      );
    }
    if (result.status != 200) {
      throw SpotifyAuthException('Spotify token endpoint returned ${result.status}');
    }

    final token = result.body['access_token'];
    if (token is! String) {
      throw const SpotifyAuthException('token response had no access_token');
    }
    // Spotify occasionally returns a rotated refresh token; keep it if so.
    final rotated = result.body['refresh_token'];
    if (rotated is String && rotated.isNotEmpty) _refreshToken = rotated;

    final expiresIn = result.body['expires_in'];
    final seconds = expiresIn is num ? expiresIn.toInt() : 3600;
    _accessToken = token;
    // Refresh 30s early so a request never rides an about-to-expire token.
    _expiresAt = _now().add(Duration(seconds: seconds - 30));
    return token;
  }

  /// The current refresh token, so a rotated one can be persisted.
  String get refreshToken => _refreshToken;
}
