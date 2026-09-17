/// The `dart:io` half of the Spotify integration: the real token endpoint and
/// the real currently-playing fetcher.
///
/// Thin adapters over [SpotifyAuth] and [SpotifyWebApiSource], both of which
/// hold the logic and are tested with these injected. Relay-only — the web
/// build never imports this, so no Spotify secret can reach a browser.
library;

import 'dart:convert';
import 'dart:io';

import 'spotify_auth.dart';
import 'spotify_web_api_source.dart';

const _tokenUrl = 'https://accounts.spotify.com/api/token';
const _currentlyPlayingUrl =
    'https://api.spotify.com/v1/me/player/currently-playing';

/// A [TokenEndpoint] that POSTs a form to Spotify's token URL.
TokenEndpoint realTokenEndpoint({
  required String clientId,
  required String clientSecret,
}) {
  final basic = 'Basic ${base64.encode(utf8.encode('$clientId:$clientSecret'))}';
  return (form) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(_tokenUrl));
      request.headers
        ..set(HttpHeaders.authorizationHeader, basic)
        ..contentType =
            ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(form.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final text = await response.transform(utf8.decoder).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(text) as Map<String, dynamic>);
      return (status: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  };
}

/// A [SpotifyFetcher] that GETs the currently-playing track with a bearer
/// token from [auth].
SpotifyFetcher realSpotifyFetcher(SpotifyAuth auth) {
  return () async {
    final String token;
    try {
      token = await auth.accessToken();
    } on SpotifyAuthException {
      // A dead token is not the same as the API being down, but from the
      // source's point of view Spotify is unreachable until it is fixed.
      return SpotifyFetchResult.unreachable;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(_currentlyPlayingUrl));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(const Duration(seconds: 10));

      // 204: nothing is playing.
      if (response.statusCode == HttpStatus.noContent) {
        await response.drain<void>();
        return const SpotifyFetchResult(null);
      }
      // 429: rate limited — honour Retry-After.
      if (response.statusCode == 429) {
        await response.drain<void>();
        final retry =
            int.tryParse(response.headers.value('retry-after') ?? '');
        return SpotifyFetchResult(null,
            retryAfter: retry == null ? null : Duration(seconds: retry));
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return SpotifyFetchResult.unreachable;
      }

      final text = await response.transform(utf8.decoder).join();
      final body = text.isEmpty
          ? null
          : jsonDecode(text) as Map<String, dynamic>;
      return SpotifyFetchResult(body);
    } on Object {
      return SpotifyFetchResult.unreachable;
    } finally {
      client.close(force: true);
    }
  };
}
