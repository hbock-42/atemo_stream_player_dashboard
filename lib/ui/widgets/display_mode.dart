/// How this instance is being looked at.
///
/// POL-01. Wall mode is entered by the URL, not by a setting: `?wall` on the
/// address the relay already serves — `http://streamplayer.local:8080/?wall`.
/// That is the whole mechanism, and it is the right one here because
///
///   * the tablet on the wall is set up once, by bookmarking a URL, with
///     nothing to re-do after a reboot or a relay redeploy;
///   * it needs no persistence, no settings screen and no gesture that a
///     passer-by could trigger by accident;
///   * the same relay, the same bundle and the same build serve both modes, so
///     there is nothing extra to deploy;
///   * `Uri.base` is the page URL on web and a harmless `file:` path on
///     native, so the native build simply never sees the flag.
///
/// `?wall=0`, `?wall=false` and `?wall=off` turn it back off, so a colleague
/// who is handed the wall URL can defuse it without editing the query string
/// down to nothing.
library;

enum DisplayMode {
  /// The phone/desktop remote: artwork, metadata, controls.
  normal,

  /// The tablet on the wall: large, no chrome, screen kept awake.
  wall,
}

/// True when [uri] asks for wall mode.
DisplayMode displayModeFromUri(Uri uri) {
  if (!uri.queryParameters.containsKey('wall')) return DisplayMode.normal;
  final value = uri.queryParameters['wall']!.toLowerCase();
  const off = {'0', 'false', 'off', 'no'};
  return off.contains(value) ? DisplayMode.normal : DisplayMode.wall;
}
