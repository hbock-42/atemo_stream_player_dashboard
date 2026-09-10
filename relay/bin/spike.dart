// This is an operator-facing console tool: stdout is the product, so a logging
// framework would be indirection for its own sake.
// ignore_for_file: avoid_print

/// Runs the EPIC-0 spikes against the real Streamplayer.
///
/// Deliberately built on the same `CastClient` the relay ships, so a green
/// spike is evidence about the code we actually run — not about a separate
/// probe that happens to work.
///
///   dart run bin/spike.dart discover [--seconds 20]
///   dart run bin/spike.dart probe    [--host <ip>] [--seconds 90]
///   dart run bin/spike.dart senders  [--host <ip>] [--max 16]
///   dart run bin/spike.dart commands [--host <ip>] --i-am-at-the-speaker
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_client.dart';
import 'package:atemo_stream_player_viewer/cast/cast_commands.dart';
import 'package:atemo_stream_player_viewer/cast/cast_message.dart';
import 'package:atemo_stream_player_viewer/cast/cast_snapshot.dart';
import 'package:atemo_stream_player_viewer/cast/namespaces.dart';
import 'package:atemo_stream_player_viewer/discovery/mdns_discovery.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('usage: dart run bin/spike.dart '
        '<discover|probe|senders|commands> [options]');
    exit(64);
  }
  final options = _parse(arguments.skip(1).toList());

  runZonedGuarded(() async {
    switch (arguments.first) {
      case 'discover':
        await _discover(int.tryParse(options['seconds'] ?? '') ?? 20);
      case 'probe':
        await _probe(options['host'], int.tryParse(options['seconds'] ?? '') ?? 90);
      case 'senders':
        await _senders(options['host'], int.tryParse(options['max'] ?? '') ?? 16);
      case 'commands':
        await _commands(options['host'], options.containsKey('i-am-at-the-speaker'));
      default:
        stderr.writeln('unknown spike: ${arguments.first}');
        exit(64);
    }
  }, (error, _) {
    // mDNS raises from its own resend timer when the host has no multicast
    // route; that is a finding, not a crash.
    if (error is SocketException && error.port == 5353) {
      stderr.writeln('! mDNS unavailable: ${error.osError?.message}');
      return;
    }
    stderr.writeln('! $error');
  });
}

// --- SPIKE-03: is the device advertising, and does it stop when idle? -------

Future<void> _discover(int seconds) async {
  _title('SPIKE-03  mDNS discovery');
  print('Browsing _googlecast._tcp for ${seconds}s. Run this while playing,');
  print('while idle, and after 30+ minutes idle. Record each answer.\n');

  final deadline = DateTime.now().add(Duration(seconds: seconds));
  var attempts = 0, found = 0;
  CastAddress? last;

  while (DateTime.now().isBefore(deadline)) {
    attempts++;
    final address = await MdnsDiscovery(timeout: const Duration(seconds: 5))
        .findStreamplayer();
    if (address != null) {
      found++;
      last = address;
      print('  ✓ $address');
    } else {
      print('  · nothing');
    }
  }

  print('\nfound on $found of $attempts browses');
  if (last != null) {
    // The question that matters: does port 8009 still answer when mDNS does
    // not? If so, a cached address is enough and DISC-04 is required.
    final reachable = await _canConnect(last.host);
    print('port 8009 reachable at ${last.host}: ${reachable ? 'yes' : 'no'}');
  }
  _record('OQ-3', 'does the record survive idle, and does 8009 answer anyway?');
}

Future<bool> _canConnect(String host) async {
  try {
    final channel = await CastChannel.connect(host)
        .timeout(const Duration(seconds: 5));
    await channel.close();
    return true;
  } on Object {
    return false;
  }
}

// --- SPIKE-01 / SPIKE-04 prep: what does each service actually publish? -----

Future<void> _probe(String? host, int seconds) async {
  _title('SPIKE-01  what surfaces on the media namespace');
  print('Watching for ${seconds}s. While this runs, play from Spotify Connect,');
  print('then Tidal Connect, then a native Cast app. Watch what changes.\n');

  final seen = <String>{};
  final client = await _connect(host, onFrame: (message) {
    final key = '${message.namespace}/${message.type}';
    // One line per new message type, then the payload once — enough to answer
    // the question without drowning in heartbeats.
    if (message.namespace == CastNamespaces.heartbeat) return;
    if (seen.add(key)) {
      print('\n── first $key');
      print(_pretty(message.json));
    }
  });

  client.updates.listen(_report);

  await Future<void>.delayed(Duration(seconds: seconds));
  await client.dispose();

  print('\nmessage types seen:');
  for (final key in seen.toList()..sort()) {
    print('  $key');
  }
  _record('OQ-1', 'for each of Spotify / Tidal / native Cast: does an app appear, '
      'and does MEDIA_STATUS carry real metadata?');
}

void _describe(CastSnapshot s) {
  final commands = <String>[
    if (s.supports(MediaCommandBits.pause)) 'pause',
    if (s.supports(MediaCommandBits.seek)) 'seek',
    if (s.supports(MediaCommandBits.queueNext)) 'next',
    if (s.supports(MediaCommandBits.queuePrevious)) 'prev',
    if (s.supports(MediaCommandBits.streamVolume)) 'stream-volume',
  ];
  final metadata = s.mediaStatus?['media'];
  print('  app=${s.appDisplayName ?? '—'} (${s.appId ?? '—'})  '
      'transport=${s.transportId ?? '—'}  session=${s.mediaSessionId ?? '—'}  '
      'volume=${s.volumeLevel}\n'
      '    supportedMediaCommands=${s.supportedMediaCommands} '
      '${commands.isEmpty ? '(none)' : '-> ${commands.join(', ')}'}\n'
      '    media=${metadata == null ? 'none' : _pretty(metadata as Map<String, dynamic>)}');
}

// --- SPIKE-02: how many senders before it misbehaves? ----------------------

Future<void> _senders(String? host, int max) async {
  _title('SPIKE-02  concurrent sender limit');
  print('Opening connections one at a time up to $max.');
  print('MUSIC MUST BE PLAYING. Watch the speaker: the outcome that matters is');
  print('whether adding senders ever disturbs playback, not just whether the');
  print('Nth connection is refused.\n');

  final address = await _resolve(host);
  final open = <CastChannel>[];

  for (var n = 1; n <= max; n++) {
    try {
      final channel = await CastChannel.connect(address.host, port: address.port)
          .timeout(const Duration(seconds: 5));
      // A connection that opens but cannot handshake is still a failure.
      channel.send(CastMessage(
        sourceId: 'spike-$n',
        destinationId: CastEndpoints.receiver,
        namespace: CastNamespaces.connection,
        payloadUtf8: jsonEncode({'type': 'CONNECT'}),
      ));
      open.add(channel);
      print('  ✓ $n connections open');
    } on Object catch (error) {
      print('  ✗ failed at connection $n: $error');
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  print('\nheld ${open.length} simultaneous connections');
  print('Leave this running a moment and confirm music is still playing,');
  print('then press Ctrl-C.');
  await Future<void>.delayed(const Duration(seconds: 20));
  for (final channel in open) {
    await channel.close();
  }
  _record('OQ-2', 'the number at which it breaks, and whether playback was disturbed');
}

// --- SPIKE-04: will it take commands from a sender that did not launch? ----

Future<void> _commands(String? host, bool confirmed) async {
  _title('SPIKE-04  commands from a foreign sender');
  if (!confirmed) {
    stderr.writeln('This one CHANGES WHAT IS PLAYING: it pauses, resumes, skips');
    stderr.writeln('and moves the volume on a real speaker in a real office.');
    stderr.writeln('Re-run with --i-am-at-the-speaker once you are ready.');
    exit(64);
  }

  print('Music must be playing, started from a DIFFERENT device.\n');
  final client = await _connect(host);
  await Future<void>.delayed(const Duration(seconds: 3));
  final commands = CastCommands(client);

  _describe(client.snapshot);
  final startingVolume = client.snapshot.volumeLevel ?? 0.3;

  await _attempt(client, 'SET_VOLUME (receiver namespace)',
      () => commands.setVolume((startingVolume + 0.05).clamp(0.0, 1.0)));
  await _attempt(client, 'PAUSE', commands.pause);
  await _attempt(client, 'PLAY', commands.play);
  await _attempt(client, 'QUEUE_NEXT', commands.next);
  await _attempt(client, 'QUEUE_PREV', commands.previous);
  await _attempt(client, 'SEEK', () => commands.seek(const Duration(seconds: 30)));

  // Put the volume back; this is someone's office.
  commands.setVolume(startingVolume);
  await Future<void>.delayed(const Duration(seconds: 1));

  commands.dispose();
  await client.dispose();
  _record('OQ-5', 'per command: accepted, silently ignored, or refused — '
      'plus the confirmation latency, which sets STATE-02\'s revert timeout');
}

void _report(CastUpdate update) {
  switch (update) {
    case CastSnapshotUpdate(:final snapshot):
      _describe(snapshot);
    case CastDisconnected(:final reason):
      print('  ! disconnected: $reason');
    case CastConnecting():
      break;
  }
}

/// Sends one command and reports whether the device confirmed it, and how fast.
Future<void> _attempt(CastClient client, String label, void Function() send) async {
  final confirmed = Completer<Duration>();
  final started = DateTime.now();
  final subscription = client.updates.listen((update) {
    if (update is CastSnapshotUpdate && !confirmed.isCompleted) {
      confirmed.complete(DateTime.now().difference(started));
    }
  });

  try {
    send();
  } on CastCommandRejectedException catch (error) {
    print('  ✗ $label — refused by us: $error');
    await subscription.cancel();
    return;
  }

  final latency = await confirmed.future
      .timeout(const Duration(seconds: 4), onTimeout: () => Duration.zero);
  await subscription.cancel();

  print(latency == Duration.zero
      ? '  · $label — sent, NO status came back (silently ignored?)'
      : '  ✓ $label — confirmed in ${latency.inMilliseconds}ms');
  await Future<void>.delayed(const Duration(seconds: 2));
}

// --- shared ----------------------------------------------------------------

Future<CastClient> _connect(String? host, {void Function(CastMessage)? onFrame}) async {
  final address = await _resolve(host);
  final client = CastClient(
    resolveAddress: ({bool forceRefresh = false}) async => address,
    onFrame: onFrame,
  );

  // Wait for the handshake rather than a fixed delay, and say so out loud when
  // it does not arrive: a spike that prints nothing at all tells you nothing
  // about the device, only that something went wrong silently.
  final connected = Completer<void>();
  final watch = client.updates.listen((update) {
    if (update is CastSnapshotUpdate && !connected.isCompleted) {
      connected.complete();
    }
    if (update is CastDisconnected) {
      stderr.writeln('  ! ${update.reason}');
    }
  });

  await client.start();
  await connected.future.timeout(const Duration(seconds: 12), onTimeout: () {
    stderr.writeln('\n  ! no response from ${address.host}:${address.port} within 12s.');
    stderr.writeln('    The device answers ping but not CASTV2? Check that nothing');
    stderr.writeln('    else is holding too many sender connections, and that this');
    stderr.writeln('    host can actually open a socket to it:');
    stderr.writeln('      nc -z ${address.host} ${address.port}');
  });
  await watch.cancel();
  return client;
}

Future<CastAddress> _resolve(String? host) async {
  if (host != null) return CastAddress(host: host);
  stdout.write('discovering… ');
  final address = await MdnsDiscovery().findStreamplayer();
  if (address == null) {
    stderr.writeln('\nnot found. Pass --host <ip> if multicast is blocked here.');
    exit(1);
  }
  print('$address');
  return address;
}

String _pretty(Map<String, dynamic> json) =>
    const JsonEncoder.withIndent('  ').convert(json);

void _title(String text) => print('\n=== $text ===\n');

void _record(String question, String what) {
  print('\n→ Record in docs/open-questions.md under $question:');
  print('  $what\n');
}

Map<String, String> _parse(List<String> arguments) {
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    if (!arguments[i].startsWith('--')) continue;
    final key = arguments[i].substring(2);
    final hasValue = i + 1 < arguments.length && !arguments[i + 1].startsWith('--');
    options[key] = hasValue ? arguments[++i] : '';
  }
  return options;
}
