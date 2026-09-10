/// An in-memory CASTV2 receiver, so protocol tests need no hardware and no
/// music playing in the office.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_message.dart';
import 'package:atemo_stream_player_viewer/cast/namespaces.dart';

/// A transport whose inbound bytes the test writes by hand, for exercising the
/// framing edge cases: two frames in one read, one frame across three reads.
class ScriptedTransport extends Stream<Uint8List> implements CastTransport {
  // Broadcast so close() completes even when the channel already cancelled.
  final StreamController<Uint8List> _inbound = StreamController<Uint8List>.broadcast();
  final List<Uint8List> written = [];
  bool closed = false;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _inbound.stream
          .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void add(Uint8List data) => written.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_inbound.isClosed) await _inbound.close();
  }

  /// Delivers raw bytes to the client, exactly as given.
  void deliver(List<int> bytes) => _inbound.add(Uint8List.fromList(bytes));

  void fail(Object error) => _inbound.addError(error);
}

/// Frames a message the way the wire does.
Uint8List frame(CastMessage message) {
  final payload = message.encode();
  final out = Uint8List(4 + payload.length);
  ByteData.view(out.buffer).setUint32(0, payload.length, Endian.big);
  out.setRange(4, out.length, payload);
  return out;
}

/// A scripted CASTV2 receiver.
class FakeCastDevice extends Stream<Uint8List> implements CastTransport {
  FakeCastDevice({
    this.appId = 'CC32E753',
    this.appDisplayName = 'Spotify',
    this.transportId = 'transport-1',
    this.sessionId = 'session-1',
    this.volumeLevel = 0.4,
    this.isMuted = false,
    this.hasApp = true,
    this.supportedMediaCommands = 1 | 2 | 64 | 128,
    Map<String, dynamic>? mediaStatus,
    this.respondToReceiverStatus = true,
    this.respondToMediaStatus = true,
    this.answerPings = true,
    this.rejectCommands = false,
  }) : mediaStatus = mediaStatus ?? defaultMediaStatus();

  String appId;
  String appDisplayName;
  String? transportId;
  String sessionId;
  double volumeLevel;
  bool isMuted;
  bool hasApp;
  int supportedMediaCommands;
  Map<String, dynamic>? mediaStatus;

  bool respondToReceiverStatus;
  bool respondToMediaStatus;
  bool answerPings;

  /// When true, media commands are accepted on the wire but produce no status
  /// change — the "silently ignored" case from SPIKE-04.
  bool rejectCommands;

  final StreamController<Uint8List> _inbound = StreamController<Uint8List>.broadcast();
  final List<CastMessage> received = <CastMessage>[];
  final BytesBuilder _buffer = BytesBuilder(copy: true);
  bool closed = false;

  List<CastMessage> get commands => received
      .where((m) =>
          m.namespace == CastNamespaces.media || m.namespace == CastNamespaces.receiver)
      .where((m) => m.type != 'GET_STATUS')
      .toList();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _inbound.stream
          .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void add(Uint8List data) {
    _buffer.add(data);
    var pending = _buffer.takeBytes();
    var offset = 0;
    while (pending.length - offset >= 4) {
      final length = ByteData.view(pending.buffer, pending.offsetInBytes + offset, 4)
          .getUint32(0, Endian.big);
      if (pending.length - offset - 4 < length) break;
      final body = Uint8List.sublistView(pending, offset + 4, offset + 4 + length);
      offset += 4 + length;
      _handle(CastMessage.decode(Uint8List.fromList(body)));
    }
    if (offset < pending.length) _buffer.add(Uint8List.sublistView(pending, offset));
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_inbound.isClosed) await _inbound.close();
  }

  /// Drops the connection the way an unplugged device does.
  Future<void> dropConnection() => close();

  void _handle(CastMessage message) {
    received.add(message);
    switch (message.namespace) {
      case CastNamespaces.heartbeat:
        if (message.type == 'PING' && answerPings) {
          push(CastNamespaces.heartbeat, CastEndpoints.receiver, {'type': 'PONG'});
        }
      case CastNamespaces.receiver:
        if (message.type == 'GET_STATUS' && respondToReceiverStatus) {
          pushReceiverStatus();
        }
        if (message.type == 'SET_VOLUME' && !rejectCommands) {
          final volume = message.json['volume'];
          if (volume is Map) {
            if (volume['level'] is num) volumeLevel = (volume['level'] as num).toDouble();
            if (volume['muted'] is bool) isMuted = volume['muted'] as bool;
          }
          pushReceiverStatus();
        }
      case CastNamespaces.media:
        if (message.type == 'GET_STATUS' && respondToMediaStatus) {
          pushMediaStatus();
        }
        if (rejectCommands) return;
        switch (message.type) {
          case 'PAUSE':
            mediaStatus = {...?mediaStatus, 'playerState': 'PAUSED'};
            pushMediaStatus();
          case 'PLAY':
            mediaStatus = {...?mediaStatus, 'playerState': 'PLAYING'};
            pushMediaStatus();
        }
    }
  }

  void pushReceiverStatus() {
    push(CastNamespaces.receiver, CastEndpoints.receiver, {
      'type': 'RECEIVER_STATUS',
      'status': {
        'volume': {'level': volumeLevel, 'muted': isMuted},
        if (hasApp)
          'applications': [
            {
              'appId': appId,
              'displayName': appDisplayName,
              'sessionId': sessionId,
              'transportId': transportId,
              'namespaces': [
                {'name': CastNamespaces.media},
              ],
            }
          ]
        else
          'applications': <Map<String, dynamic>>[],
      },
    });
  }

  void pushMediaStatus() {
    final status = mediaStatus;
    push(CastNamespaces.media, transportId ?? 'transport-1', {
      'type': 'MEDIA_STATUS',
      'status': status == null
          ? <Map<String, dynamic>>[]
          : [
              {
                'mediaSessionId': 1,
                'supportedMediaCommands': supportedMediaCommands,
                ...status,
              }
            ],
    });
  }

  /// Simulates someone switching from Spotify to Tidal.
  void switchApp({
    required String newAppId,
    required String newDisplayName,
    required String newTransportId,
  }) {
    appId = newAppId;
    appDisplayName = newDisplayName;
    transportId = newTransportId;
    mediaStatus = defaultMediaStatus(title: 'A Different Track', artist: 'Someone Else');
    pushReceiverStatus();
  }

  /// Simulates the casting app quitting.
  void quitApp() {
    hasApp = false;
    transportId = null;
    mediaStatus = null;
    pushReceiverStatus();
  }

  void push(String namespace, String source, Map<String, dynamic> payload) {
    if (_inbound.isClosed) return;
    _inbound.add(frame(CastMessage(
      sourceId: source,
      destinationId: 'sender-0',
      namespace: namespace,
      payloadUtf8: jsonEncode(payload),
    )));
  }

  static Map<String, dynamic> defaultMediaStatus({
    String? title = 'Waltz for Debby',
    String? artist = 'Bill Evans Trio',
    String? album = 'Waltz for Debby',
    String playerState = 'PLAYING',
  }) =>
      {
        'playerState': playerState,
        'currentTime': 42.5,
        'media': {
          'duration': 396.0,
          'metadata': {
            'title': ?title,
            'artist': ?artist,
            'albumName': ?album,
            'images': [
              {'url': 'http://192.168.1.50:8008/artwork.jpg'},
            ],
          },
        },
      };
}
