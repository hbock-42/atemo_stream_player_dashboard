/// Entry point for the relay.
///
/// Usage:
///   dart run bin/relay.dart [--port 8080] [--web ../build/web] [--host 1.2.3.4]
library;

import 'dart:async';
import 'dart:io';

import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/data/direct_cast_source.dart';
import 'package:atemo_stream_player_viewer/discovery/mdns_discovery.dart';
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

  final discovery = MdnsDiscovery();
  CastAddress? cached;

  final source = DirectCastSource(
    resolveAddress: ({bool forceRefresh = false}) async {
      final manual = options['host'];
      if (manual != null) return CastAddress(host: manual, friendlyName: 'Streamplayer');
      if (!forceRefresh && cached != null) return cached;
      cached = await discovery.findStreamplayer();
      return cached;
    },
  );

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

  await server.start();
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
