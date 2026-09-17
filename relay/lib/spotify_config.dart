/// Loads the relay's Spotify credentials from a gitignored JSON file.
///
/// Shape (relay/spotify.json — never committed):
///   {
///     "clientId": "...",
///     "clientSecret": "...",
///     "refreshToken": "...",     // written by `just spotify-setup`
///     "deviceName": "The Kids"   // the Spotify device to watch; optional
///   }
library;

import 'dart:convert';
import 'dart:io';

class SpotifyConfig {
  const SpotifyConfig({
    required this.clientId,
    required this.clientSecret,
    required this.refreshToken,
    this.deviceName,
  });

  final String clientId;
  final String clientSecret;
  final String refreshToken;
  final String? deviceName;

  bool get isComplete =>
      clientId.isNotEmpty && clientSecret.isNotEmpty && refreshToken.isNotEmpty;

  static const defaultPath = 'spotify.json';

  /// Loads from [path], or null if the file is absent. Throws on a present but
  /// malformed file — a silent skip there would hide a typo the user needs to
  /// fix.
  static SpotifyConfig? load([String path = defaultPath]) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return SpotifyConfig(
      clientId: (json['clientId'] as String?) ?? '',
      clientSecret: (json['clientSecret'] as String?) ?? '',
      refreshToken: (json['refreshToken'] as String?) ?? '',
      deviceName: json['deviceName'] as String?,
    );
  }

  /// Rewrites [path] with a (possibly rotated) refresh token, preserving the
  /// rest.
  void saveRefreshToken(String token, [String path = defaultPath]) {
    File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'clientId': clientId,
      'clientSecret': clientSecret,
      'refreshToken': token,
      if (deviceName != null) 'deviceName': deviceName,
    }));
  }
}
