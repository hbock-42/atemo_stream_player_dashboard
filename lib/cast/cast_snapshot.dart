/// The protocol-level view of the device: what the receiver and media
/// namespaces last told us.
///
/// This is deliberately *not* the domain model. It holds raw media status JSON
/// for `data/media_status_mapper.dart` to interpret, and parses only what the
/// protocol layer itself needs — the ids required to address commands, and the
/// device volume.
library;

/// Bit values of `supportedMediaCommands`.
///
/// Verify against the real device in SPIKE-04 before relying on the less
/// common ones; the two we lean on hardest are PAUSE and the queue commands.
class MediaCommandBits {
  const MediaCommandBits._();

  static const int pause = 1;
  static const int seek = 2;
  static const int streamVolume = 4;
  static const int streamMute = 8;
  static const int queueNext = 64;
  static const int queuePrevious = 128;
}

class CastSnapshot {
  const CastSnapshot({
    this.appId,
    this.appDisplayName,
    this.sessionId,
    this.transportId,
    this.mediaSessionId,
    this.volumeLevel,
    this.isMuted = false,
    this.supportedMediaCommands = 0,
    this.mediaStatus,
    this.deviceName,
  });

  final String? appId;
  final String? appDisplayName;
  final String? sessionId;
  final String? transportId;
  final int? mediaSessionId;

  /// Device volume, 0.0–1.0. From the receiver namespace, so it is present
  /// even when no app is running.
  final double? volumeLevel;
  final bool isMuted;

  final int supportedMediaCommands;

  /// Raw `status[0]` from the last MEDIA_STATUS. Interpreted by the mapper.
  final Map<String, dynamic>? mediaStatus;

  final String? deviceName;

  /// True when an app is running that isn't the idle Backdrop.
  bool get hasApp => transportId != null;

  /// True when we can address transport commands at something.
  bool get canSendMediaCommands => transportId != null && mediaSessionId != null;

  bool supports(int bit) => supportedMediaCommands & bit == bit;

  CastSnapshot copyWith({
    String? appId,
    String? appDisplayName,
    String? sessionId,
    String? transportId,
    int? mediaSessionId,
    double? volumeLevel,
    bool? isMuted,
    int? supportedMediaCommands,
    Map<String, dynamic>? mediaStatus,
    String? deviceName,
    bool clearApp = false,
    bool clearMedia = false,
  }) {
    return CastSnapshot(
      appId: clearApp ? null : (appId ?? this.appId),
      appDisplayName: clearApp ? null : (appDisplayName ?? this.appDisplayName),
      sessionId: clearApp ? null : (sessionId ?? this.sessionId),
      transportId: clearApp ? null : (transportId ?? this.transportId),
      mediaSessionId:
          (clearApp || clearMedia) ? null : (mediaSessionId ?? this.mediaSessionId),
      volumeLevel: volumeLevel ?? this.volumeLevel,
      isMuted: isMuted ?? this.isMuted,
      supportedMediaCommands: (clearApp || clearMedia)
          ? 0
          : (supportedMediaCommands ?? this.supportedMediaCommands),
      mediaStatus: (clearApp || clearMedia) ? null : (mediaStatus ?? this.mediaStatus),
      deviceName: deviceName ?? this.deviceName,
    );
  }

  @override
  String toString() => 'CastSnapshot(app: $appDisplayName, transport: $transportId, '
      'mediaSession: $mediaSessionId, volume: $volumeLevel, muted: $isMuted)';
}
