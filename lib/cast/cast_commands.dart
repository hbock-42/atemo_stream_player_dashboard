/// The command half of the CASTV2 client.
///
/// Deliberately narrow. Volume goes to `receiver-0` and works with no app
/// running; transport commands go to the current session and are gated on
/// `supportedMediaCommands` so we never fire a command the running app has
/// told us it does not support.
///
/// LAUNCH and LOAD are absent by design and must stay that way — they would
/// evict whatever the office is listening to. Enforced by tool/check_layers.sh.
library;

import 'dart:async';

import 'cast_client.dart';
import 'cast_snapshot.dart';

class CastCommands {
  CastCommands(this._client, {this.volumeRateLimit = const Duration(milliseconds: 100)});

  final CastClient _client;

  /// Cheap hardware will not thank you for sixty messages a second from a
  /// dragged slider.
  final Duration volumeRateLimit;

  Timer? _volumeTimer;
  DateTime? _lastVolumeSentAt;
  double? _pendingVolume;

  CastSnapshot get _snapshot => _client.snapshot;

  // --- device volume: always available ---------------------------------------

  /// Sets device volume, 0.0–1.0.
  ///
  /// Rate-limited, but the final value is always transmitted: a drag that ends
  /// inside the rate-limit window still lands on the value the user chose.
  void setVolume(double level) {
    final clamped = level.clamp(0.0, 1.0).toDouble();
    final now = DateTime.now();
    final last = _lastVolumeSentAt;

    if (last == null || now.difference(last) >= volumeRateLimit) {
      _volumeTimer?.cancel();
      _volumeTimer = null;
      _pendingVolume = null;
      _lastVolumeSentAt = now;
      _client.sendReceiverCommand({
        'type': 'SET_VOLUME',
        'volume': {'level': clamped},
      });
      return;
    }

    _pendingVolume = clamped;
    _volumeTimer ??= Timer(volumeRateLimit - now.difference(last), _flushVolume);
  }

  void _flushVolume() {
    _volumeTimer = null;
    final pending = _pendingVolume;
    if (pending == null) return;
    _pendingVolume = null;
    _lastVolumeSentAt = DateTime.now();
    try {
      _client.sendReceiverCommand({
        'type': 'SET_VOLUME',
        'volume': {'level': pending},
      });
    } on CastCommandRejectedException {
      // The connection went away mid-drag. The next status will correct the UI.
    }
  }

  void setMuted(bool muted) {
    _client.sendReceiverCommand({
      'type': 'SET_VOLUME',
      'volume': {'muted': muted},
    });
  }

  // --- transport: capability-gated -------------------------------------------

  void play() => _sendMedia('PLAY', MediaCommandBits.pause);

  void pause() => _sendMedia('PAUSE', MediaCommandBits.pause);

  void next() => _sendMedia('QUEUE_NEXT', MediaCommandBits.queueNext);

  void previous() => _sendMedia('QUEUE_PREV', MediaCommandBits.queuePrevious);

  void seek(Duration position) {
    _requireCapability(MediaCommandBits.seek, 'seeking');
    _client.sendMediaCommand({
      'type': 'SEEK',
      'currentTime': position.inMilliseconds / 1000.0,
    });
  }

  /// Implemented for completeness and deliberately not exposed to the UI:
  /// too easy to mis-tap, and recovery needs the phone that started the
  /// session. See ADR-0004.
  void stopSession() {
    _client.sendMediaCommand({'type': 'STOP'});
  }

  void _sendMedia(String type, int requiredBit) {
    _requireCapability(requiredBit, _describe(type));
    _client.sendMediaCommand({'type': type});
  }

  void _requireCapability(int bit, String what) {
    if (!_snapshot.canSendMediaCommands) {
      throw const CastCommandRejectedException('nothing is playing');
    }
    if (!_snapshot.supports(bit)) {
      throw CastCommandRejectedException(
        'the app currently casting does not support $what',
      );
    }
  }

  String _describe(String type) => switch (type) {
        'PLAY' || 'PAUSE' => 'pausing',
        'QUEUE_NEXT' => 'skipping forward',
        'QUEUE_PREV' => 'skipping back',
        _ => type.toLowerCase(),
      };

  void dispose() {
    _volumeTimer?.cancel();
    _volumeTimer = null;
    _pendingVolume = null;
  }
}
