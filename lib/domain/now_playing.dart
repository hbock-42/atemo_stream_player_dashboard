/// What the UI knows about. No Cast vocabulary appears here or above it.
library;

/// What the currently-casting app allows us to do.
///
/// Decoded from `supportedMediaCommands`. The UI renders unsupported controls
/// disabled rather than firing commands that silently do nothing.
class Capabilities {
  const Capabilities({
    this.canPause = false,
    this.canSeek = false,
    this.canSkipNext = false,
    this.canSkipPrevious = false,
  });

  static const none = Capabilities();

  final bool canPause;
  final bool canSeek;
  final bool canSkipNext;
  final bool canSkipPrevious;

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other.canPause == canPause &&
      other.canSeek == canSeek &&
      other.canSkipNext == canSkipNext &&
      other.canSkipPrevious == canSkipPrevious;

  @override
  int get hashCode => Object.hash(canPause, canSeek, canSkipNext, canSkipPrevious);

  Map<String, dynamic> toJson() => {
        'canPause': canPause,
        'canSeek': canSeek,
        'canSkipNext': canSkipNext,
        'canSkipPrevious': canSkipPrevious,
      };

  static Capabilities fromJson(Map<String, dynamic> json) => Capabilities(
        canPause: json['canPause'] == true,
        canSeek: json['canSeek'] == true,
        canSkipNext: json['canSkipNext'] == true,
        canSkipPrevious: json['canSkipPrevious'] == true,
      );
}

/// The state of the speaker.
///
/// [Idle] and [Unreachable] are separate types on purpose. "Nothing is
/// playing" and "I cannot see the speaker" look the same in a nullable model
/// and must never look the same to a user.
sealed class NowPlaying {
  const NowPlaying();

  Map<String, dynamic> toJson();

  static NowPlaying fromJson(Map<String, dynamic> json) => switch (json['state']) {
        'playing' => Playing.fromJson(json),
        'idle' => Idle.fromJson(json),
        'unreachable' => Unreachable.fromJson(json),
        _ => Connecting(deviceName: json['deviceName'] as String?),
      };
}

class Connecting extends NowPlaying {
  const Connecting({this.deviceName});

  final String? deviceName;

  @override
  Map<String, dynamic> toJson() => {'state': 'connecting', 'deviceName': deviceName};

  @override
  bool operator ==(Object other) => other is Connecting && other.deviceName == deviceName;

  @override
  int get hashCode => deviceName.hashCode;
}

class Playing extends NowPlaying {
  const Playing({
    this.title,
    this.artist,
    this.album,
    this.artworkUrl,
    this.castingApp,
    this.isPaused = false,
    this.position,
    this.duration,
    this.volumeLevel,
    this.isMuted = false,
    this.capabilities = Capabilities.none,
    this.deviceName,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? artworkUrl;

  /// "Spotify", "Tidal", … as reported by the receiver.
  final String? castingApp;

  final bool isPaused;
  final Duration? position;
  final Duration? duration;

  /// Device volume, 0.0–1.0.
  final double? volumeLevel;
  final bool isMuted;

  final Capabilities capabilities;
  final String? deviceName;

  /// True when the device gave us a session but no usable metadata — worth
  /// showing differently from a full card.
  bool get hasMetadata => (title ?? artist ?? album) != null;

  @override
  Map<String, dynamic> toJson() => {
        'state': 'playing',
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'castingApp': castingApp,
        'isPaused': isPaused,
        'positionMs': position?.inMilliseconds,
        'durationMs': duration?.inMilliseconds,
        'volumeLevel': volumeLevel,
        'isMuted': isMuted,
        'capabilities': capabilities.toJson(),
        'deviceName': deviceName,
      };

  static Playing fromJson(Map<String, dynamic> json) => Playing(
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        artworkUrl: json['artworkUrl'] as String?,
        castingApp: json['castingApp'] as String?,
        isPaused: json['isPaused'] == true,
        position: _duration(json['positionMs']),
        duration: _duration(json['durationMs']),
        volumeLevel: (json['volumeLevel'] as num?)?.toDouble(),
        isMuted: json['isMuted'] == true,
        capabilities: json['capabilities'] is Map<String, dynamic>
            ? Capabilities.fromJson(json['capabilities'] as Map<String, dynamic>)
            : Capabilities.none,
        deviceName: json['deviceName'] as String?,
      );

  Playing copyWith({
    bool? isPaused,
    double? volumeLevel,
    bool? isMuted,
  }) =>
      Playing(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        castingApp: castingApp,
        isPaused: isPaused ?? this.isPaused,
        position: position,
        duration: duration,
        volumeLevel: volumeLevel ?? this.volumeLevel,
        isMuted: isMuted ?? this.isMuted,
        capabilities: capabilities,
        deviceName: deviceName,
      );

  @override
  bool operator ==(Object other) =>
      other is Playing &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.artworkUrl == artworkUrl &&
      other.castingApp == castingApp &&
      other.isPaused == isPaused &&
      other.position == position &&
      other.duration == duration &&
      other.volumeLevel == volumeLevel &&
      other.isMuted == isMuted &&
      other.capabilities == capabilities &&
      other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(title, artist, album, artworkUrl, castingApp, isPaused,
      position, duration, volumeLevel, isMuted, capabilities, deviceName);
}

/// The device is reachable but nothing is playing.
///
/// Carries volume, because device volume works with no app running and the
/// idle screen still offers a working control.
class Idle extends NowPlaying {
  const Idle({this.deviceName, this.volumeLevel, this.isMuted = false});

  final String? deviceName;
  final double? volumeLevel;
  final bool isMuted;

  @override
  Map<String, dynamic> toJson() => {
        'state': 'idle',
        'deviceName': deviceName,
        'volumeLevel': volumeLevel,
        'isMuted': isMuted,
      };

  static Idle fromJson(Map<String, dynamic> json) => Idle(
        deviceName: json['deviceName'] as String?,
        volumeLevel: (json['volumeLevel'] as num?)?.toDouble(),
        isMuted: json['isMuted'] == true,
      );

  Idle copyWith({double? volumeLevel, bool? isMuted}) => Idle(
        deviceName: deviceName,
        volumeLevel: volumeLevel ?? this.volumeLevel,
        isMuted: isMuted ?? this.isMuted,
      );

  @override
  bool operator ==(Object other) =>
      other is Idle &&
      other.deviceName == deviceName &&
      other.volumeLevel == volumeLevel &&
      other.isMuted == isMuted;

  @override
  int get hashCode => Object.hash(deviceName, volumeLevel, isMuted);
}

/// The device cannot be seen at all.
class Unreachable extends NowPlaying {
  Unreachable({required this.reason, DateTime? since}) : since = since ?? DateTime.now();

  final String reason;
  final DateTime since;

  @override
  Map<String, dynamic> toJson() => {
        'state': 'unreachable',
        'reason': reason,
        'since': since.toIso8601String(),
      };

  static Unreachable fromJson(Map<String, dynamic> json) => Unreachable(
        reason: json['reason'] as String? ?? 'unknown',
        since: DateTime.tryParse(json['since'] as String? ?? ''),
      );

  @override
  bool operator ==(Object other) => other is Unreachable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

Duration? _duration(Object? milliseconds) =>
    milliseconds is num ? Duration(milliseconds: milliseconds.toInt()) : null;
