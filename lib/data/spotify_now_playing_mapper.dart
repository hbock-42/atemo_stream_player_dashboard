/// Maps a Spotify Web API `/v1/me/player/currently-playing` response to the
/// domain's [NowPlaying].
///
/// Spotify Connect is invisible to Cast on this device (OQ-1), so this is the
/// only way to see a Spotify track. The Web API returns what is playing on the
/// user's account across all their devices, so the mapper filters to the
/// Streamplayer by device name — otherwise someone's phone playing in their
/// pocket would show as the office speaker.
///
/// Pure, so it is tested against captured API response shapes with no network.
library;

import '../domain/now_playing.dart';

class SpotifyNowPlayingMapper {
  const SpotifyNowPlayingMapper({this.deviceName});

  /// When set, a track is only reported if it is playing on a Spotify device
  /// whose name contains this (case-insensitive). Null shows whatever is
  /// playing on the account, wherever.
  final String? deviceName;

  /// [json] is the parsed currently-playing body, or null for a 204 (nothing
  /// playing). [reachable] is false when the API itself could not be reached.
  NowPlaying map(Map<String, dynamic>? json, {bool reachable = true}) {
    if (!reachable) {
      return Unreachable(reason: 'cannot reach Spotify');
    }
    if (json == null || json.isEmpty) {
      return const Idle(deviceName: 'Spotify');
    }

    // Only count it if it is on our speaker. A track playing on someone's
    // phone must not masquerade as the office system.
    final device = _map(json['device']);
    if (deviceName != null) {
      final playingOn = _string(device?['name']);
      if (playingOn == null ||
          !playingOn.toLowerCase().contains(deviceName!.toLowerCase())) {
        return const Idle(deviceName: 'Spotify');
      }
    }

    final item = _map(json['item']);
    if (item == null) {
      // Playing something with no track object — an ad, or a local file. Honest
      // to call it idle rather than invent a title.
      return const Idle(deviceName: 'Spotify');
    }

    final isPlaying = json['is_playing'] == true;
    final album = _map(item['album']);
    final volumeRaw = device?['volume_percent'];

    return Playing(
      title: _string(item['name']),
      artist: _artists(item['artists']),
      album: _string(album?['name']),
      artworkUrl: _firstImage(album?['images']),
      castingApp: 'Spotify',
      isPaused: !isPlaying,
      position: _ms(json['progress_ms']),
      duration: _ms(item['duration_ms']),
      volumeLevel: volumeRaw is num ? volumeRaw / 100.0 : null,
      // The Web API can pause/skip/seek/set-volume with the right scopes; the
      // source decides whether to expose control based on what it was granted.
      capabilities: const Capabilities(
        canPause: true,
        canSeek: true,
        canSkipNext: true,
        canSkipPrevious: true,
      ),
      deviceName: _string(device?['name']),
    );
  }

  static String? _artists(Object? artists) {
    if (artists is! List) return null;
    final names = artists
        .whereType<Map>()
        .map((a) => _string(a['name']))
        .whereType<String>()
        .toList();
    return names.isEmpty ? null : names.join(', ');
  }

  static String? _firstImage(Object? images) {
    if (images is! List) return null;
    for (final image in images) {
      if (image is Map) {
        final url = _string(image['url']);
        if (url != null) return url;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static String? _string(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static Duration? _ms(Object? v) => v is num ? Duration(milliseconds: v.toInt()) : null;
}
