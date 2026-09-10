/// The CASTV2 client: handshake, heartbeat, session tracking and reconnect.
///
/// Adopts whatever session is already running on the device. It never sends
/// LAUNCH or LOAD — doing so would evict whatever the office is listening to.
/// See ADR-0001 and ADR-0004.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'cast_address.dart';
import 'cast_channel.dart';
import 'cast_message.dart';
import 'cast_snapshot.dart';
import 'namespaces.dart';

/// Resolves the device's address. `forceRefresh` asks the caller to bypass any
/// cache and re-run discovery, which the client requests once reconnects have
/// failed enough times to suggest the device has moved.
typedef CastAddressResolver = Future<CastAddress?> Function({bool forceRefresh});

typedef CastChannelFactory = Future<CastChannel> Function(CastAddress address);

sealed class CastUpdate {
  const CastUpdate();
}

class CastConnecting extends CastUpdate {
  const CastConnecting();
}

class CastSnapshotUpdate extends CastUpdate {
  const CastSnapshotUpdate(this.snapshot);
  final CastSnapshot snapshot;
}

class CastDisconnected extends CastUpdate {
  const CastDisconnected(this.reason, {this.detail});

  /// Phrased for a person looking at the screen.
  final String reason;

  /// The underlying error, verbatim. The friendly reason is useless for
  /// diagnosis — "could not reach the Streamplayer" hides whether the socket
  /// was refused, timed out, or blocked by the OS, which are three different
  /// problems with three different fixes.
  final Object? detail;
}

class CastUnavailableException implements Exception {
  const CastUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raised when a command cannot be sent. Callers use this to revert optimistic
/// UI immediately rather than waiting for the confirmation timeout.
class CastCommandRejectedException implements Exception {
  const CastCommandRejectedException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CastClient {
  CastClient({
    required this.resolveAddress,
    CastChannelFactory? channelFactory,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.livenessTimeout = const Duration(seconds: 15),
    this.connectTimeout = const Duration(seconds: 5),
    this.onFrame,
    Random? random,
  })  : _channelFactory = channelFactory ??
            ((address) => CastChannel.connect(address.host, port: address.port)),
        _random = random ?? Random();

  final CastAddressResolver resolveAddress;
  final CastChannelFactory _channelFactory;
  final Duration heartbeatInterval;
  final Duration livenessTimeout;
  final Duration connectTimeout;

  /// Every inbound frame, before interpretation. Used by the spike tool to
  /// answer questions the parsed snapshot cannot — such as whether a Spotify
  /// Connect session says anything at all on the media namespace.
  final void Function(CastMessage message)? onFrame;

  final Random _random;

  final StreamController<CastUpdate> _updates = StreamController<CastUpdate>.broadcast();
  final String _sourceId = 'sender-${DateTime.now().microsecondsSinceEpoch % 100000000}';
  final Set<String> _openConnections = <String>{};

  CastChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _livenessTimer;
  Completer<void>? _sessionDone;
  Future<void>? _loopFuture;
  int _requestId = 1;
  bool _disposed = false;

  CastSnapshot _snapshot = const CastSnapshot();
  CastAddress? _address;
  DateTime? _lastMessageAt;

  Stream<CastUpdate> get updates => _updates.stream;
  CastSnapshot get snapshot => _snapshot;
  bool get isConnected => _channel != null;

  /// The address we last connected to — kept after a drop, because "which box
  /// did you find?" is the first diagnostic question.
  CastAddress? get address => _address;

  /// When the device last sent us anything, of any kind. Since the heartbeat
  /// runs every few seconds, a long gap here means the socket is dead even if
  /// TCP has not admitted it yet.
  DateTime? get lastMessageAt => _lastMessageAt;

  Future<void> start() async {
    if (_disposed || _loopFuture != null) return;
    _loopFuture = _runLoop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _teardownSession();
    await _loopFuture;
    if (!_updates.isClosed) await _updates.close();
  }

  // --- connection loop -------------------------------------------------------

  Future<void> _runLoop() async {
    var failureStreak = 0;

    while (!_disposed) {
      _emit(const CastConnecting());
      try {
        // Three failures in a row suggests the device moved rather than that
        // it is briefly busy, so stop trusting the cached address.
        final address = await resolveAddress(forceRefresh: failureStreak >= 3);
        if (address == null) {
          throw const CastUnavailableException('Streamplayer not found on the network');
        }
        await _serve(address);
        // We had a working connection, so the next retry should be prompt.
        failureStreak = 0;
        if (!_disposed) _emit(const CastDisconnected('connection closed'));
      } catch (error) {
        failureStreak++;
        _teardownSession();
        if (!_disposed) _emit(CastDisconnected(_describe(error), detail: error));
      }

      if (_disposed) break;
      await _backoff(failureStreak);
    }
  }

  Future<void> _serve(CastAddress address) async {
    final channel = await _channelFactory(address).timeout(connectTimeout);
    _channel = channel;
    _address = address;
    _openConnections.clear();
    _snapshot = CastSnapshot(deviceName: address.friendlyName);

    final done = Completer<void>();
    _sessionDone = done;

    final subscription = channel.messages.listen(
      _onMessage,
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    try {
      _connectTo(CastEndpoints.receiver);
      _sendJson(
        CastNamespaces.receiver,
        CastEndpoints.receiver,
        {'type': 'GET_STATUS'},
      );
      _startHeartbeat();
      _resetLiveness();
      await done.future;
    } finally {
      await subscription.cancel();
      _teardownSession();
    }
  }

  Future<void> _backoff(int failureStreak) async {
    const schedule = [1, 2, 4, 8, 16, 30];
    final seconds = schedule[min(failureStreak, schedule.length - 1)];
    // Jitter keeps a roomful of clients from retrying in lockstep after the
    // device power-cycles.
    final jitterMs = _random.nextInt(500);
    await Future<void>.delayed(Duration(seconds: seconds, milliseconds: jitterMs));
  }

  void _teardownSession() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _livenessTimer?.cancel();
    _livenessTimer = null;
    _openConnections.clear();
    final channel = _channel;
    _channel = null;
    unawaited(channel?.close());
    final done = _sessionDone;
    _sessionDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  // --- heartbeat -------------------------------------------------------------

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _sendJson(CastNamespaces.heartbeat, CastEndpoints.receiver, {'type': 'PING'});
    });
  }

  /// Any inbound traffic counts as proof of life. Silence for longer than
  /// [livenessTimeout] means the socket is dead even though TCP has not
  /// noticed — common when a device is unplugged rather than shut down.
  void _resetLiveness() {
    _livenessTimer?.cancel();
    _livenessTimer = Timer(livenessTimeout, () {
      final done = _sessionDone;
      if (done != null && !done.isCompleted) {
        done.completeError(
          const CastUnavailableException('no response from the device'),
        );
      }
    });
  }

  // --- inbound ---------------------------------------------------------------

  void _onMessage(CastMessage message) {
    _lastMessageAt = DateTime.now();
    _resetLiveness();

    switch (message.namespace) {
      case CastNamespaces.heartbeat:
        if (message.type == 'PING') {
          _sendJson(CastNamespaces.heartbeat, CastEndpoints.receiver, {'type': 'PONG'});
        }
      case CastNamespaces.connection:
        if (message.type == 'CLOSE') {
          _onConnectionClosed(message.sourceId);
        }
      case CastNamespaces.receiver:
        if (message.type == 'RECEIVER_STATUS') {
          _onReceiverStatus(message.json);
        }
      case CastNamespaces.media:
        if (message.type == 'MEDIA_STATUS') {
          _onMediaStatus(message.json);
        }
    }
  }

  void _onConnectionClosed(String from) {
    if (from == CastEndpoints.receiver) {
      final done = _sessionDone;
      if (done != null && !done.isCompleted) done.complete();
      return;
    }
    if (from == _snapshot.transportId) {
      // The app closed its session. Not a connection failure — the device is
      // fine and simply idle now.
      _openConnections.remove(from);
      _snapshot = _snapshot.copyWith(clearApp: true);
      _emit(CastSnapshotUpdate(_snapshot));
    }
  }

  void _onReceiverStatus(Map<String, dynamic> payload) {
    final status = payload['status'];
    if (status is! Map) return;

    final volume = status['volume'];
    final level = volume is Map ? _asDouble(volume['level']) : null;
    final muted = volume is Map && volume['muted'] == true;

    final application = _firstApplication(status['applications']);

    if (application == null) {
      // No app, or Backdrop: the device is idle. Volume still applies.
      if (_snapshot.hasApp) {
        _closeConnection(_snapshot.transportId!);
      }
      _snapshot = _snapshot.copyWith(
        volumeLevel: level,
        isMuted: muted,
        clearApp: true,
      );
      _emit(CastSnapshotUpdate(_snapshot));
      return;
    }

    final transportId = application['transportId'] as String?;
    final previousTransportId = _snapshot.transportId;

    _snapshot = _snapshot.copyWith(
      appId: application['appId'] as String?,
      appDisplayName: application['displayName'] as String?,
      sessionId: application['sessionId'] as String?,
      transportId: transportId,
      volumeLevel: level,
      isMuted: muted,
      // A new session means the old media status is stale.
      clearMedia: transportId != previousTransportId,
    );

    if (transportId != null && transportId != previousTransportId) {
      if (previousTransportId != null) _closeConnection(previousTransportId);
      _connectTo(transportId);
      _sendJson(CastNamespaces.media, transportId, {'type': 'GET_STATUS'});
    }

    _emit(CastSnapshotUpdate(_snapshot));
  }

  void _onMediaStatus(Map<String, dynamic> payload) {
    final statusList = payload['status'];
    if (statusList is! List || statusList.isEmpty) {
      // An empty status list is how some receivers report "nothing loaded".
      _snapshot = _snapshot.copyWith(clearMedia: true);
      _emit(CastSnapshotUpdate(_snapshot));
      return;
    }

    final status = statusList.first;
    if (status is! Map) return;
    final typed = Map<String, dynamic>.from(status);

    _snapshot = _snapshot.copyWith(
      mediaSessionId: _asInt(typed['mediaSessionId']) ?? _snapshot.mediaSessionId,
      supportedMediaCommands: _asInt(typed['supportedMediaCommands']) ?? 0,
      mediaStatus: typed,
    );
    _emit(CastSnapshotUpdate(_snapshot));
  }

  /// The first application that isn't the idle Backdrop.
  Map<String, dynamic>? _firstApplication(Object? applications) {
    if (applications is! List) return null;
    for (final entry in applications) {
      if (entry is! Map) continue;
      final appId = entry['appId'];
      final displayName = entry['displayName'];
      if (appId == kBackdropAppId || displayName == kBackdropDisplayName) continue;
      if (entry['transportId'] is! String) continue;
      return Map<String, dynamic>.from(entry);
    }
    return null;
  }

  // --- outbound --------------------------------------------------------------

  void _connectTo(String destination) {
    if (_openConnections.contains(destination)) return;
    _openConnections.add(destination);
    _sendJson(CastNamespaces.connection, destination, {
      'type': 'CONNECT',
      // Identifying ourselves honestly; some receivers log it.
      'userAgent': 'streamplayer-viewer',
    });
  }

  void _closeConnection(String destination) {
    if (!_openConnections.remove(destination)) return;
    _sendJson(CastNamespaces.connection, destination, {'type': 'CLOSE'});
  }

  int _nextRequestId() => _requestId++;

  void _sendJson(String namespace, String destination, Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    channel.send(CastMessage(
      sourceId: _sourceId,
      destinationId: destination,
      namespace: namespace,
      payloadUtf8: jsonEncode(payload),
    ));
  }

  /// Sends a receiver-namespace command to `receiver-0`.
  ///
  /// This is how device volume is set, and it works with no app running.
  void sendReceiverCommand(Map<String, dynamic> payload) {
    if (_channel == null) {
      throw const CastCommandRejectedException('not connected to the device');
    }
    _sendJson(CastNamespaces.receiver, CastEndpoints.receiver, {
      ...payload,
      'requestId': _nextRequestId(),
    });
  }

  /// Sends a media-namespace command to the current session.
  ///
  /// Refuses rather than sending when there is no session to address, so a
  /// command is never emitted without a `mediaSessionId`.
  void sendMediaCommand(Map<String, dynamic> payload) {
    final transportId = _snapshot.transportId;
    final mediaSessionId = _snapshot.mediaSessionId;
    if (_channel == null) {
      throw const CastCommandRejectedException('not connected to the device');
    }
    if (transportId == null || mediaSessionId == null) {
      throw const CastCommandRejectedException('nothing is playing');
    }
    _sendJson(CastNamespaces.media, transportId, {
      ...payload,
      'mediaSessionId': mediaSessionId,
      'requestId': _nextRequestId(),
    });
  }

  void _emit(CastUpdate update) {
    if (!_updates.isClosed) _updates.add(update);
  }

  String _describe(Object error) => switch (error) {
        CastUnavailableException(:final message) => message,
        TimeoutException() => 'the device did not respond in time',
        _ => 'could not reach the Streamplayer',
      };
}

double? _asDouble(Object? value) => switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

int? _asInt(Object? value) => switch (value) {
      final int i => i,
      final num n => n.toInt(),
      final String s => int.tryParse(s),
      _ => null,
    };
