import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_client.dart';
import 'package:atemo_stream_player_viewer/cast/namespaces.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atemo_stream_player_viewer/testing/fake_cast_device.dart';

/// Lets the event loop drain. The handshake is several round trips through
/// stream controllers, none of which involve real time.
Future<void> settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeCastDevice device;
  late CastClient client;

  CastClient buildClient({FakeCastDevice? withDevice}) {
    device = withDevice ?? FakeCastDevice();
    return CastClient(
      resolveAddress: ({bool forceRefresh = false}) async =>
          const CastAddress(host: '192.168.1.50', friendlyName: 'Streamplayer'),
      channelFactory: (_) async => CastChannel.fromTransport(device),
      heartbeatInterval: const Duration(milliseconds: 50),
      livenessTimeout: const Duration(milliseconds: 400),
    );
  }

  tearDown(() async => client.dispose());

  test('handshake reaches a playing session without launching anything', () async {
    client = buildClient();
    await client.start();
    await settle();

    final snapshot = client.snapshot;
    expect(snapshot.appDisplayName, 'Spotify');
    expect(snapshot.transportId, 'transport-1');
    expect(snapshot.mediaSessionId, 1);
    expect(snapshot.volumeLevel, 0.4);
    expect(snapshot.mediaStatus?['playerState'], 'PLAYING');

    // The handshake order from protocol.md: CONNECT to receiver-0, GET_STATUS
    // on the receiver namespace, CONNECT to the transport, GET_STATUS on media.
    final sent = device.received;
    expect(sent[0].namespace, CastNamespaces.connection);
    expect(sent[0].destinationId, CastEndpoints.receiver);
    expect(sent[1].namespace, CastNamespaces.receiver);
    expect(sent[1].type, 'GET_STATUS');
    expect(
      sent.any((m) =>
          m.namespace == CastNamespaces.connection && m.destinationId == 'transport-1'),
      isTrue,
    );
    expect(
      sent.any((m) => m.namespace == CastNamespaces.media && m.type == 'GET_STATUS'),
      isTrue,
    );

    // The guarantee that matters: we never evict the running session.
    expect(sent.any((m) => m.type == 'LAUNCH' || m.type == 'LOAD'), isFalse);
  });

  test('answers PING with PONG', () async {
    client = buildClient();
    await client.start();
    await settle();

    device.push(CastNamespaces.heartbeat, CastEndpoints.receiver, {'type': 'PING'});
    await settle();

    expect(device.received.any((m) => m.type == 'PONG'), isTrue);
  });

  test('follows an app change to a new transport', () async {
    client = buildClient();
    await client.start();
    await settle();

    device.switchApp(
      newAppId: 'TIDAL',
      newDisplayName: 'Tidal',
      newTransportId: 'transport-2',
    );
    await settle();
    device.pushMediaStatus();
    await settle();

    expect(client.snapshot.appDisplayName, 'Tidal');
    expect(client.snapshot.transportId, 'transport-2');
    expect(client.snapshot.mediaStatus?['media']['metadata']['title'], 'A Different Track');

    // The old virtual connection is closed and a new one opened.
    expect(
      device.received.any((m) =>
          m.namespace == CastNamespaces.connection &&
          m.type == 'CLOSE' &&
          m.destinationId == 'transport-1'),
      isTrue,
    );
    expect(
      device.received.any((m) =>
          m.namespace == CastNamespaces.connection &&
          m.type == 'CONNECT' &&
          m.destinationId == 'transport-2'),
      isTrue,
    );
  });

  test('clears the session when the app quits, without stale metadata', () async {
    client = buildClient();
    await client.start();
    await settle();
    expect(client.snapshot.hasApp, isTrue);

    device.quitApp();
    await settle();

    expect(client.snapshot.hasApp, isFalse);
    expect(client.snapshot.mediaStatus, isNull);
    expect(client.snapshot.mediaSessionId, isNull);
    // Volume survives: it is device-level and still controllable while idle.
    expect(client.snapshot.volumeLevel, 0.4);
  });

  test('treats a Backdrop application as idle', () async {
    final backdrop = FakeCastDevice(
      appId: kBackdropAppId,
      appDisplayName: kBackdropDisplayName,
    );
    client = buildClient(withDevice: backdrop);
    await client.start();
    await settle();

    expect(client.snapshot.hasApp, isFalse);
    expect(client.snapshot.volumeLevel, 0.4);
  });

  test('reports disconnection when the socket drops', () async {
    client = buildClient();
    final updates = <CastUpdate>[];
    client.updates.listen(updates.add);
    await client.start();
    await settle();

    await device.dropConnection();
    await settle();

    expect(updates.whereType<CastDisconnected>(), isNotEmpty);
  });

  test('times out when the device stops responding', () async {
    final silent = FakeCastDevice(answerPings: false, respondToReceiverStatus: false);
    client = buildClient(withDevice: silent);
    final updates = <CastUpdate>[];
    client.updates.listen(updates.add);
    await client.start();

    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(
      updates.whereType<CastDisconnected>().any((u) => u.reason.contains('no response')),
      isTrue,
    );
  });

  test('refuses a media command when nothing is playing', () async {
    final idle = FakeCastDevice(hasApp: false);
    client = buildClient(withDevice: idle);
    await client.start();
    await settle();

    expect(
      () => client.sendMediaCommand({'type': 'PAUSE'}),
      throwsA(isA<CastCommandRejectedException>()),
    );
  });

  test('never emits a media command without a mediaSessionId', () async {
    client = buildClient();
    await client.start();
    await settle();

    client.sendMediaCommand({'type': 'PAUSE'});
    await settle();

    final pause = device.received.firstWhere((m) => m.type == 'PAUSE');
    expect(pause.json['mediaSessionId'], 1);
    expect(pause.json['requestId'], isA<int>());
  });
}
