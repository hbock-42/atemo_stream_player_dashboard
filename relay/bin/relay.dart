/// Entry point for the relay.
///
/// Usage:
///   dart run bin/relay.dart [--port 8080] [--web ../build/web] [--host 1.2.3.4]
library;

import 'dart:async';
import 'dart:io';

import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_client.dart';
import 'package:atemo_stream_player_viewer/data/direct_cast_source.dart';
import 'package:atemo_stream_player_viewer/discovery/mdns_discovery.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing_source.dart';
import 'package:atemo_stream_player_viewer/testing/fake_cast_device.dart';
import 'package:streamplayer_relay/relay_server.dart';

Future<void> main(List<String> arguments) async {
  // The relay is a single point of failure for the whole office and is meant
  // to run for weeks unattended. An unhandled async error from a socket must
  // be logged, not fatal.
  runZonedGuarded(() => _run(arguments), (error, stack) {
    final now = DateTime.now().toIso8601String();
    // multicast_dns raises this from its own resend timer when the host has no
    // multicast route. Expected whenever the device is absent or the network
    // blocks multicast, and already handled — discovery returns null and the
    // client retries — so it does not deserve a stack trace every few seconds.
    if (error is SocketException && error.port == 5353) {
      stderr.writeln('$now relay: mDNS unavailable (${error.osError?.message})');
      return;
    }
    stderr.writeln('$now relay: unhandled $error');
    stderr.writeln(stack);
  });
}

Future<void> _run(List<String> arguments) async {
  final options = _parse(arguments);

  // --demo runs the whole stack against the in-memory fake device: real
  // client, real mapper, real fan-out, no speaker. Useful for working on the
  // UI, and for showing people what this will look like before it is deployed.
  if (options.containsKey('demo')) {
    await _serve(_demoSource(), options);
    return;
  }

  final discovery = MdnsDiscovery();
  CastAddress? cached;

  var warned = false;
  final source = DirectCastSource(
    resolveAddress: ({bool forceRefresh = false}) async {
      final manual = options['host'];
      if (manual != null) return CastAddress(host: manual, friendlyName: 'Streamplayer');
      if (!forceRefresh && cached != null) return cached;
      cached = await discovery.findStreamplayer();

      if (cached == null && !warned) {
        warned = true;
        // Retrying silently forever looks identical to a broken relay. Say
        // what to try, once.
        stderr
          ..writeln('')
          ..writeln('  Could not find the Streamplayer over mDNS.')
          ..writeln('  Either it is powered off, or this network blocks multicast.')
          ..writeln('  Find it by hand and skip discovery:')
          ..writeln('      dns-sd -B _googlecast._tcp local')
          ..writeln('      dart run bin/relay.dart --host <its-ip> --web ../build/web')
          ..writeln('  Still retrying in the background.')
          ..writeln('');
      } else if (cached != null) {
        warned = false;
        stdout.writeln('  Found the Streamplayer at $cached');
      }
      return cached;
    },
  );

  await _serve(source, options);
}

DirectCastSource _demoSource() {
  final device = FakeCastDevice();

  // Change the track periodically so the display is visibly alive.
  const tracks = [
    ('Waltz for Debby', 'Bill Evans Trio', 'Waltz for Debby', 'Spotify'),
    ('Blue in Green', 'Miles Davis', 'Kind of Blue', 'Deezer'),
    ('Everything In Its Right Place', 'Radiohead', 'Kid A', 'SoundCloud'),
    ('Teardrop', 'Massive Attack', 'Mezzanine', 'Tidal'),
  ];
  var index = 0;
  Timer.periodic(const Duration(seconds: 12), (_) {
    index = (index + 1) % tracks.length;
    final (title, artist, album, app) = tracks[index];
    device
      ..appDisplayName = app
      ..mediaStatus = FakeCastDevice.defaultMediaStatus(
          title: title, artist: artist, album: album)
      ..pushReceiverStatus()
      ..pushMediaStatus();
  });

  return DirectCastSource(
    resolveAddress: ({bool forceRefresh = false}) async =>
        const CastAddress(host: 'demo', friendlyName: 'Streamplayer (demo)'),
    client: CastClient(
      resolveAddress: ({bool forceRefresh = false}) async =>
          const CastAddress(host: 'demo'),
      channelFactory: (_) async => CastChannel.fromTransport(device),
      heartbeatInterval: const Duration(seconds: 30),
    ),
  );
}

Future<void> _serve(NowPlayingSource source, Map<String, String?> options) async {
  final webPath = options['web'];
  final server = RelayServer(
    source: source,
    port: int.tryParse(options['port'] ?? '') ?? 8080,
    webRoot: webPath == null ? null : Directory(webPath),
  );

  // Shut down cleanly so the device sees the connection close rather than
  // holding a dead sender until its own timeout.
  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nshutting down');
    await server.stop();
    exit(0);
  });

  try {
    await server.start();
  } on SocketException catch (error) {
    // A stack trace for "something else is already listening" tells the reader
    // nothing they can act on.
    if (error.osError?.errorCode == 48 || error.osError?.errorCode == 98) {
      stderr
        ..writeln('')
        ..writeln('  Port ${server.port} is already in use.')
        ..writeln('  Something else is listening — very likely another copy of')
        ..writeln('  this relay. Find it, or pick another port:')
        ..writeln('      lsof -nP -iTCP:${server.port} -sTCP:LISTEN')
        ..writeln('      pkill -f bin/relay.dart')
        ..writeln('      dart run bin/relay.dart --port 8081 --web ../build/web')
        ..writeln('');
      exit(1);
    }
    stderr.writeln('  Could not start the relay: $error');
    exit(1);
  }
}

Map<String, String?> _parse(List<String> arguments) {
  final options = <String, String?>{};
  for (var i = 0; i < arguments.length - 1; i++) {
    if (arguments[i].startsWith('--')) {
      options[arguments[i].substring(2)] = arguments[i + 1];
    }
  }
  return options;
}
