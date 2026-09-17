// ignore_for_file: avoid_print
/// One-time Spotify authorisation for the relay.
///
///   1. Create an app at https://developer.spotify.com/dashboard
///   2. Add redirect URI  http://127.0.0.1:8888/callback
///   3. Put clientId and clientSecret in relay/spotify.json
///   4. Run:  just spotify-setup   (or  dart run bin/spotify_setup.dart)
///
/// It opens the consent page, captures the code Spotify redirects back, swaps
/// it for a refresh token, and writes that into relay/spotify.json. After this
/// the relay picks Spotify up automatically. See docs/spotify.md.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atemo_stream_player_viewer/data/spotify_io.dart';
import 'package:streamplayer_relay/spotify_config.dart';

const _redirect = 'http://127.0.0.1:8888/callback';
// Read scopes are what the source uses today; the modify scope is requested
// now so control can be added later without re-authorising.
const _scopes = 'user-read-playback-state user-read-currently-playing '
    'user-modify-playback-state';

Future<void> main() async {
  final config = SpotifyConfig.load();
  if (config == null || config.clientId.isEmpty || config.clientSecret.isEmpty) {
    stderr.writeln('Put clientId and clientSecret in relay/spotify.json first — '
        'see docs/spotify.md.');
    exit(64);
  }

  final authorizeUrl = Uri.https('accounts.spotify.com', '/authorize', {
    'client_id': config.clientId,
    'response_type': 'code',
    'redirect_uri': _redirect,
    'scope': _scopes,
  });

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
  print('\nOpen this in a browser and approve:\n\n  $authorizeUrl\n');
  // Best effort — on a headless box the user opens it themselves.
  unawaited(Process.run('open', [authorizeUrl.toString()]));

  final request = await server.first.timeout(const Duration(minutes: 5),
      onTimeout: () => throw StateError('timed out waiting for the redirect'));
  final code = request.uri.queryParameters['code'];
  final error = request.uri.queryParameters['error'];

  request.response
    ..headers.contentType = ContentType.html
    ..write(error != null
        ? '<h2>Authorisation failed: $error</h2>'
        : '<h2>Done. You can close this tab.</h2>');
  await request.response.close();
  await server.close(force: true);

  if (code == null) {
    stderr.writeln('No code returned (${error ?? "unknown error"}).');
    exit(1);
  }

  final exchange =
      realTokenEndpoint(clientId: config.clientId, clientSecret: config.clientSecret);
  final result = await exchange({
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': _redirect,
  });

  if (result.status != 200) {
    stderr.writeln('Token exchange failed (${result.status}): ${jsonEncode(result.body)}');
    exit(1);
  }
  final refresh = result.body['refresh_token'];
  if (refresh is! String) {
    stderr.writeln('No refresh_token in the response.');
    exit(1);
  }

  config.saveRefreshToken(refresh);
  print('\nSaved the refresh token to relay/spotify.json.');
  print('The relay will now show Spotify. Restart it if it is running.\n');
  exit(0);
}
