/// Finds the Streamplayer on the LAN.
///
/// The device advertises `_googlecast._tcp` with an instance name of the form
/// `Streamplayer-<32 hex chars>` — confirmed with dns-sd. Google Cast is the
/// only usable way in: Atonemo publishes no API, and AirPlay 2 receivers do
/// not expose now-playing metadata to third parties.
library;

import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../cast/cast_address.dart';
import 'multicast_lock.dart';

const String kCastService = '_googlecast._tcp.local';

/// Matches the instance names this device publishes.
final RegExp kStreamplayerInstance = RegExp(r'Streamplayer-[0-9a-fA-F]{32}');

class MdnsDiscovery {
  MdnsDiscovery({
    this.timeout = const Duration(seconds: 5),
    this.lock = const NoopMulticastLock(),
  });

  final Duration timeout;

  /// Android needs a real one; the relay and iOS do not.
  final MulticastLock lock;

  /// Returns the first Streamplayer found, or null if none appears before the
  /// timeout. Never hangs: a device that is off must produce a decision, not a
  /// spinner that lasts forever.
  Future<CastAddress?> findStreamplayer() {
    // Errors are absorbed on the inner future rather than around the timeout.
    // Once timeout has substituted its own result, a later failure of the
    // original future has no listener and surfaces as an unhandled async
    // error — which takes the whole process down. A multicast socket the
    // platform refuses is indistinguishable from "not found" to the caller
    // anyway.
    final browse = _withLock(_browse).then<CastAddress?>(
      (address) => address,
      onError: (Object _, StackTrace _) => null,
    );
    return browse.timeout(timeout, onTimeout: () => null);
  }

  /// Releases the lock even when the browse throws or times out.
  Future<CastAddress?> _withLock(Future<CastAddress?> Function() action) async {
    await lock.acquire();
    try {
      return await action();
    } finally {
      await lock.release();
    }
  }

  /// Binds the multicast socket, retrying without `reusePort`.
  ///
  /// `multicast_dns` asks for `reusePort: true`, which several platforms —
  /// macOS among them — refuse. The package exists to be overridden here, and
  /// the retry is the difference between discovery working on someone's laptop
  /// and silently finding nothing.
  static Future<RawDatagramSocket> _bind(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 255,
  }) async {
    try {
      return await RawDatagramSocket.bind(host, port,
          reuseAddress: reuseAddress, reusePort: reusePort, ttl: ttl);
    } on SocketException {
      return RawDatagramSocket.bind(host, port,
          reuseAddress: reuseAddress, reusePort: false, ttl: ttl);
    }
  }

  Future<CastAddress?> _browse() async {
    final client = MDnsClient(rawDatagramSocketFactory: _bind);
    await client.start();
    try {
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(kCastService),
      )) {
        final instance = ptr.domainName;
        if (!kStreamplayerInstance.hasMatch(instance)) continue;

        final address = await _resolve(client, instance);
        if (address != null) return address;
      }
    } finally {
      client.stop();
    }
    return null;
  }

  Future<CastAddress?> _resolve(MDnsClient client, String instance) async {
    await for (final srv in client.lookup<SrvResourceRecord>(
      ResourceRecordQuery.service(instance),
    )) {
      await for (final record in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
      )) {
        return CastAddress(
          host: record.address.address,
          // The advertised port is authoritative, but 8009 is the CASTV2 port
          // and what the device actually listens on.
          port: srv.port == 0 ? kDefaultCastPort : srv.port,
          friendlyName: await _friendlyName(client, instance) ?? _instanceLabel(instance),
        );
      }
    }
    return null;
  }

  /// The TXT record's `fn` is the name the owner gave the device.
  Future<String?> _friendlyName(MDnsClient client, String instance) async {
    final txt = await _txt(client, instance);
    final name = txt['fn']?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  /// The device's whole TXT record, as key/value pairs.
  ///
  /// Worth more than it looks. Alongside `fn`, this device publishes `st`
  /// (whether an app is running) and `rs` (a human-readable status line such
  /// as `Casting: <track>`). That is now-playing information over plain mDNS,
  /// with no CASTV2 connection and no sender slot consumed — a service-agnostic
  /// fallback if a Connect protocol turns out to be silent on the media
  /// namespace. See OQ-1.
  Future<Map<String, String>> readTxtRecord({String? instance}) async {
    final client = MDnsClient(rawDatagramSocketFactory: _bind);
    await client.start();
    try {
      final name = instance ?? await _findInstance(client);
      if (name == null) return const {};
      return await _txt(client, name);
    } on Exception {
      return const {};
    } finally {
      client.stop();
    }
  }

  Future<String?> _findInstance(MDnsClient client) async {
    await for (final ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(kCastService),
    )) {
      if (kStreamplayerInstance.hasMatch(ptr.domainName)) return ptr.domainName;
    }
    return null;
  }

  Future<Map<String, String>> _txt(MDnsClient client, String instance) async {
    try {
      await for (final txt in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(instance),
      )) {
        return parseTxt(txt.text);
      }
    } on Exception {
      // TXT is a nicety; never let it fail the discovery.
    }
    return const {};
  }

  /// Splits a TXT record's newline-separated `key=value` lines.
  ///
  /// Pure, so it can be tested without a network: values may contain `=`
  /// (a status line can), keys may repeat, and a malformed line must be
  /// skipped rather than throwing.
  static Map<String, String> parseTxt(String text) {
    final entries = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final split = trimmed.indexOf('=');
      if (split <= 0) continue;
      entries[trimmed.substring(0, split)] = trimmed.substring(split + 1);
    }
    return entries;
  }

  String _instanceLabel(String instance) =>
      instance.split('.').first.replaceAll(RegExp(r'-[0-9a-fA-F]{32}$'), '');
}
