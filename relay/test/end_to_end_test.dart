/// The whole chain, with nothing stubbed in the middle.
///
/// Every other test cuts the system somewhere: the app's tests stop at a fake
/// source, the relay's stop at a stub source. This one runs a fake CASTV2
/// device, the real CastClient, the real DirectCastSource and mapper, the real
/// RelayServer, a real WebSocket, and the real RelaySource a browser would use.
///
/// It is the only thing that would catch the relay and the client disagreeing
/// about the wire format, which is exactly the kind of break that survives two
/// green unit suites.
library;

import 'dart:async';

import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_client.dart';
import 'package:atemo_stream_player_viewer/data/direct_cast_source.dart';
import 'package:atemo_stream_player_viewer/data/relay_source.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/testing/fake_cast_device.dart';
import 'package:streamplayer_relay/relay_server.dart';
import 'package:test/test.dart';

void main() {
  late FakeCastDevice device;
  late DirectCastSource deviceSide;
  late RelayServer relay;
  late RelaySource browserSide;

  setUp(() async {
    device = FakeCastDevice();
    deviceSide = DirectCastSource(
      resolveAddress: ({bool forceRefresh = false}) async =>
          const CastAddress(host: 'fake', friendlyName: 'Streamplayer'),
      client: CastClient(
        resolveAddress: ({bool forceRefresh = false}) async =>
            const CastAddress(host: 'fake'),
        channelFactory: (_) async => CastChannel.fromTransport(device),
        heartbeatInterval: const Duration(seconds: 30),
      ),
    );

    relay = RelayServer(source: deviceSide, port: 0);
    await relay.start();

    browserSide = RelaySource(url: 'ws://127.0.0.1:${relay.boundPort}/ws');
    await browserSide.start();
  });

  tearDown(() async {
    await browserSide.dispose();
    await relay.stop();
  });

  /// Waits for a state the browser side considers final, rather than sleeping.
  Future<T> waitFor<T extends NowPlaying>(bool Function(T) predicate) =>
      browserSide.stream
          .where((state) => state is T && predicate(state))
          .cast<T>()
          .first
          .timeout(const Duration(seconds: 10));

  test('a track on the device reaches a browser client', () async {
    final playing = await waitFor<Playing>((p) => p.title != null);

    expect(playing.title, 'Waltz for Debby');
    expect(playing.artist, 'Bill Evans Trio');
    expect(playing.album, 'Waltz for Debby');
    expect(playing.castingApp, 'Spotify');
    expect(playing.isPaused, isFalse);
    expect(playing.volumeLevel, 0.4);
    expect(playing.capabilities.canPause, isTrue,
        reason: 'supportedMediaCommands must survive the whole chain, '
            'or the browser renders controls it cannot use');
  });

  test('artwork and timings survive serialisation', () async {
    final playing = await waitFor<Playing>((p) => p.artworkUrl != null);

    expect(playing.artworkUrl, 'http://192.168.1.50:8008/artwork.jpg');
    expect(playing.duration, const Duration(seconds: 396));
    expect(playing.position, const Duration(milliseconds: 42500));
  });

  test('pressing pause in the browser reaches the device', () async {
    await waitFor<Playing>((p) => p.title != null);

    browserSide.control!.pause();

    final paused = await waitFor<Playing>((p) => p.isPaused);
    expect(paused.isPaused, isTrue);
    expect(device.received.any((m) => m.type == 'PAUSE'), isTrue,
        reason: 'the command must actually reach the device, not just the UI');
    // And it carried the session the device is expecting.
    final pause = device.received.firstWhere((m) => m.type == 'PAUSE');
    expect(pause.json['mediaSessionId'], 1);
  });

  test('volume set in the browser reaches the device', () async {
    await waitFor<Playing>((p) => p.title != null);

    browserSide.control!.setVolume(0.85);

    await waitFor<Playing>((p) => (p.volumeLevel ?? 0) > 0.8);
    expect(device.volumeLevel, closeTo(0.85, 0.001));
  });

  test('a track change on the device reaches the browser', () async {
    await waitFor<Playing>((p) => p.title == 'Waltz for Debby');

    device
      ..mediaStatus = FakeCastDevice.defaultMediaStatus(
        title: 'Blue in Green', artist: 'Miles Davis')
      ..pushMediaStatus();

    final next = await waitFor<Playing>((p) => p.title == 'Blue in Green');
    expect(next.artist, 'Miles Davis');
  });

  test('an app change reaches the browser with the new attribution', () async {
    await waitFor<Playing>((p) => p.castingApp == 'Spotify');

    device.switchApp(
      newAppId: 'DEEZER', newDisplayName: 'Deezer', newTransportId: 'transport-2');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    device.pushMediaStatus();

    final next = await waitFor<Playing>((p) => p.castingApp == 'Deezer');
    expect(next.title, 'A Different Track');
  });

  test('the app quitting shows idle, not a stale track', () async {
    await waitFor<Playing>((p) => p.title != null);

    device.quitApp();

    final idle = await waitFor<Idle>((_) => true);
    // Device volume is addressed to the receiver, so it survives the app going.
    expect(idle.volumeLevel, 0.4);
  });

  test('the device dropping shows unreachable, and only then', () async {
    await waitFor<Playing>((p) => p.title != null);

    await device.dropConnection();

    final gone = await waitFor<Unreachable>((_) => true);
    expect(gone.reason, isNotEmpty);
  });

  test('a second browser client sees the same state', () async {
    await waitFor<Playing>((p) => p.title != null);

    final second = RelaySource(url: 'ws://127.0.0.1:${relay.boundPort}/ws');
    await second.start();
    addTearDown(second.dispose);

    final seen = await second.stream
        .where((s) => s is Playing && s.title != null)
        .cast<Playing>()
        .first
        .timeout(const Duration(seconds: 10));

    expect(seen.title, 'Waltz for Debby');
    expect(relay.clientCount, 2);
  });
}
