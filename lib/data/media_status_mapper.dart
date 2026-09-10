/// Turns a protocol-level [CastSnapshot] into the domain's [NowPlaying].
///
/// Every field here is read defensively. The device is cheap hardware with no
/// published API contract; a missing key, a null, a wrong type or an empty
/// array must degrade to a partial card, never to an exception. A malformed
/// payload must not blank the display mid-song.
library;

import '../cast/cast_snapshot.dart';
import '../domain/now_playing.dart';

class MediaStatusMapper {
  const MediaStatusMapper();

  NowPlaying map(CastSnapshot snapshot) {
    final volumeLevel = snapshot.volumeLevel;
    final isMuted = snapshot.isMuted;

    if (!snapshot.hasApp) {
      return Idle(
        deviceName: snapshot.deviceName,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
      );
    }

    final status = snapshot.mediaStatus;
    if (status == null) {
      // An app is running but has not reported any media yet — either we are
      // still mid-handshake, or the app is open with nothing loaded.
      return Idle(
        deviceName: snapshot.deviceName,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
      );
    }

    final playerState = _string(status['playerState'])?.toUpperCase();
    if (playerState == 'IDLE') {
      return Idle(
        deviceName: snapshot.deviceName,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
      );
    }

    final media = _map(status['media']);
    final metadata = _map(media?['metadata']);

    return Playing(
      title: _string(metadata?['title']),
      // albumArtist is what several apps populate when artist is absent.
      artist: _string(metadata?['artist']) ??
          _string(metadata?['albumArtist']) ??
          _string(metadata?['songArtist']),
      album: _string(metadata?['albumName']),
      artworkUrl: _firstImageUrl(metadata?['images']),
      castingApp: snapshot.appDisplayName,
      // BUFFERING is still "playing" from the user's point of view.
      isPaused: playerState == 'PAUSED',
      position: _seconds(status['currentTime']),
      duration: _seconds(media?['duration']),
      volumeLevel: volumeLevel,
      isMuted: isMuted,
      capabilities: capabilitiesFrom(snapshot.supportedMediaCommands),
      deviceName: snapshot.deviceName,
    );
  }

  static Capabilities capabilitiesFrom(int supportedMediaCommands) => Capabilities(
        canPause: supportedMediaCommands & MediaCommandBits.pause != 0,
        canSeek: supportedMediaCommands & MediaCommandBits.seek != 0,
        canSkipNext: supportedMediaCommands & MediaCommandBits.queueNext != 0,
        canSkipPrevious: supportedMediaCommands & MediaCommandBits.queuePrevious != 0,
      );

  static String? _firstImageUrl(Object? images) {
    if (images is! List) return null;
    for (final image in images) {
      if (image is! Map) continue;
      final url = _string(image['url']);
      if (url != null) return url;
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  /// Empty strings become null: an empty title should render as absent, not as
  /// a blank line where a title ought to be.
  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Duration? _seconds(Object? value) {
    final number = switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    if (number == null || number.isNaN || number.isInfinite || number < 0) return null;
    return Duration(milliseconds: (number * 1000).round());
  }
}
