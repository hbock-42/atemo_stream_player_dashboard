import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_client.dart';
import 'package:atemo_stream_player_viewer/cast/cast_commands.dart';
import 'package:atemo_stream_player_viewer/cast/cast_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atemo_stream_player_viewer/testing/fake_cast_device.dart';

Future<void> settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeCastDevice device;
  late CastClient client;
  late CastCommands commands;

  Future<void> connect({
    int supportedMediaCommands = MediaCommandBits.pause |
        MediaCommandBits.seek |
        MediaCommandBits.queueNext |
        MediaCommandBits.queuePrevious,
    bool hasApp = true,
  }) async {
    device = FakeCastDevice(
      supportedMediaCommands: supportedMediaCommands,
      hasApp: hasApp,
    );
    client = CastClient(
      resolveAddress: ({bool forceRefresh = false}) async =>
          const CastAddress(host: '192.168.1.50'),
      channelFactory: (_) async => CastChannel.fromTransport(device),
      heartbeatInterval: const Duration(seconds: 30),
    );
    commands = CastCommands(client, volumeRateLimit: const Duration(milliseconds: 50));
    await client.start();
    await settle();
  }

  tearDown(() async {
    commands.dispose();
    await client.dispose();
  });

  group('device volume', () {
    test('is sent to receiver-0 and works with no app running', () async {
      await connect(hasApp: false);

      commands.setVolume(0.75);
      await settle();

      final sent = device.received.firstWhere((m) => m.type == 'SET_VOLUME');
      expect(sent.destinationId, 'receiver-0');
      expect((sent.json['volume'] as Map)['level'], 0.75);
      expect(device.volumeLevel, 0.75);
    });

    test('clamps out-of-range values', () async {
      await connect();
      commands.setVolume(1.8);
      await settle();
      expect(device.volumeLevel, 1.0);
    });

    test('rate-limits a drag but always lands on the final value', () async {
      await connect();

      // Sixty events, as a real drag produces.
      for (var i = 0; i <= 60; i++) {
        commands.setVolume(i / 60);
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final volumeMessages = device.received.where((m) => m.type == 'SET_VOLUME').toList();
      expect(volumeMessages.length, lessThan(10),
          reason: 'a dragged slider must not flood the device');
      expect(device.volumeLevel, closeTo(1.0, 0.0001),
          reason: 'the value the user settled on must be the one transmitted');
    });

    test('mute round-trips', () async {
      await connect();
      commands.setMuted(true);
      await settle();
      expect(device.isMuted, isTrue);
    });
  });

  group('capability gating', () {
    test('pause is sent when supported', () async {
      await connect();
      commands.pause();
      await settle();

      expect(device.received.any((m) => m.type == 'PAUSE'), isTrue);
      expect(client.snapshot.mediaStatus?['playerState'], 'PAUSED');
    });

    test('skip is refused, and not sent, when unsupported', () async {
      await connect(supportedMediaCommands: MediaCommandBits.pause);

      expect(() => commands.next(), throwsA(isA<CastCommandRejectedException>()));
      await settle();

      expect(device.received.any((m) => m.type == 'QUEUE_NEXT'), isFalse,
          reason: 'an unsupported command must never reach the wire');
    });

    test('the rejection explains itself in words a user could read', () async {
      await connect(supportedMediaCommands: MediaCommandBits.pause);

      expect(
        () => commands.next(),
        throwsA(isA<CastCommandRejectedException>().having(
          (e) => e.message,
          'message',
          contains('does not support skipping forward'),
        )),
      );
    });

    test('every transport command is refused when nothing is playing', () async {
      await connect(hasApp: false);

      for (final command in <void Function()>[
        commands.play,
        commands.pause,
        commands.next,
        commands.previous,
        () => commands.seek(const Duration(seconds: 10)),
      ]) {
        expect(command, throwsA(isA<CastCommandRejectedException>()));
      }
      await settle();

      expect(device.commands.where((m) => m.namespace.endsWith('media')), isEmpty);
    });
  });

  test('no command family can express LAUNCH or LOAD', () async {
    await connect();

    commands
      ..play()
      ..pause()
      ..next()
      ..previous()
      ..seek(const Duration(seconds: 5))
      ..setVolume(0.3)
      ..setMuted(false);
    await settle();

    expect(
      device.received.any((m) => m.type == 'LAUNCH' || m.type == 'LOAD'),
      isFalse,
    );
  });
}
