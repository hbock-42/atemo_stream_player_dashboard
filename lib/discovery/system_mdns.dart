/// mDNS via the operating system's own tool, for machines where Dart cannot.
///
/// On at least one managed Mac, every Dart socket to the LAN is refused with
/// `No route to host` while Apple's `dns-sd` works perfectly — see OQ-9. Since
/// `dns-sd` is an Apple-signed system binary it is exempt from whatever blocks
/// us, so shelling out to it is the difference between the app working on that
/// machine and not working at all.
///
/// This only recovers what mDNS can tell us: the device's address and its TXT
/// record, which is enough for [TxtStatusSource]. A CASTV2 connection still
/// needs a socket Dart can open.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../cast/cast_address.dart';
import 'mdns_discovery.dart';

class SystemMdns {
  const SystemMdns({this.timeout = const Duration(seconds: 6)});

  final Duration timeout;

  /// Whether the platform has a tool we know how to drive.
  static bool get isSupported => Platform.isMacOS;

  Future<CastAddress?> findStreamplayer() async {
    final instance = await _firstStreamplayer();
    if (instance == null) return null;

    final resolved = await _resolve(instance);
    final host = resolved?.host;
    if (host == null) return null;

    final ip = await _addressOf(host);
    if (ip == null) return null;

    return CastAddress(
      host: ip,
      port: resolved?.port ?? kDefaultCastPort,
      friendlyName: resolved?.txt['fn'] ?? _label(instance),
    );
  }

  Future<Map<String, String>> readTxtRecord() async {
    final instance = await _firstStreamplayer();
    if (instance == null) return const {};
    return (await _resolve(instance))?.txt ?? const {};
  }

  // --- running the tool ------------------------------------------------------

  /// `dns-sd` never exits on its own — it browses until killed — so every call
  /// runs it for [timeout] and then stops it.
  Future<String> _run(List<String> arguments) async {
    final buffer = StringBuffer();
    Process? process;
    try {
      process = await Process.start('dns-sd', arguments);
      final done = Completer<void>();
      process.stdout.transform(utf8.decoder).listen(buffer.write,
          onDone: () => done.isCompleted ? null : done.complete());
      await Future.any([
        done.future,
        Future<void>.delayed(timeout),
      ]);
    } on ProcessException {
      return '';
    } finally {
      process?.kill();
    }
    return buffer.toString();
  }

  Future<String?> _firstStreamplayer() async {
    final names = parseBrowse(await _run(['-B', '_googlecast._tcp', 'local']));
    return names.isEmpty ? null : names.first;
  }

  Future<({String? host, int? port, Map<String, String> txt})?> _resolve(
      String instance) async {
    final output = await _run(['-L', instance, '_googlecast._tcp', 'local']);
    final resolved = parseResolve(output);
    return resolved.txt.isEmpty && resolved.host == null ? null : resolved;
  }

  Future<String?> _addressOf(String host) async =>
      parseAddress(await _run(['-G', 'v4', host]));

  static String _label(String instance) =>
      instance.split('.').first.replaceAll(RegExp(r'-[0-9a-fA-F]{32}$'), '');

  // --- parsing, kept pure so it can be tested without the tool ---------------

  /// Instance names from `dns-sd -B` output, in the order they were added.
  static List<String> parseBrowse(String output) {
    final names = <String>[];
    for (final line in output.split('\n')) {
      // Timestamp  A/R  Flags  if  Domain  Service Type  Instance Name
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 7 || fields[1] != 'Add') continue;
      final name = fields.sublist(6).join(' ');
      if (kStreamplayerInstance.hasMatch(name) && !names.contains(name)) {
        names.add(name);
      }
    }
    return names;
  }

  /// Host, port and TXT record from `dns-sd -L` output.
  static ({String? host, int? port, Map<String, String> txt}) parseResolve(
      String output) {
    String? host;
    int? port;
    var txt = <String, String>{};

    for (final line in output.split('\n')) {
      final reached = RegExp(r'can be reached at\s+(\S+?):(\d+)').firstMatch(line);
      if (reached != null) {
        host = reached.group(1)!.replaceAll(RegExp(r'\.$'), '');
        port = int.tryParse(reached.group(2)!);
        continue;
      }
      // The TXT record is the indented line of key=value pairs that follows.
      if (line.startsWith(' ') && line.contains('=')) {
        final parsed = parseEscapedTxt(line);
        if (parsed.isNotEmpty) txt = parsed;
      }
    }
    return (host: host, port: port, txt: txt);
  }

  /// Splits `dns-sd`'s space-separated TXT pairs.
  ///
  /// Values contain spaces, and the tool escapes them with a backslash —
  /// `rs=Casting:\ Matières\ #1` is one pair, not four.
  static Map<String, String> parseEscapedTxt(String line) {
    final pairs = <String>[];
    final current = StringBuffer();
    var escaped = false;

    for (final rune in line.trim().runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        current.write(char);
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == ' ') {
        if (current.isNotEmpty) pairs.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) pairs.add(current.toString());

    final entries = <String, String>{};
    for (final pair in pairs) {
      final split = pair.indexOf('=');
      if (split <= 0) continue;
      entries[pair.substring(0, split)] = pair.substring(split + 1);
    }
    return entries;
  }

  /// The IPv4 address from `dns-sd -G v4` output.
  static String? parseAddress(String output) {
    for (final line in output.split('\n')) {
      if (!line.contains('Add')) continue;
      final match =
          RegExp(r'\b((?:\d{1,3}\.){3}\d{1,3})\b').firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }
}
