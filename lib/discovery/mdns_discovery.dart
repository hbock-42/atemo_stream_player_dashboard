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
import '../cast/cast_channel.dart';
import 'multicast_lock.dart';

const String kCastService = '_googlecast._tcp.local';

/// Matches the instance names this device publishes.
final RegExp kStreamplayerInstance = RegExp(r'Streamplayer-[0-9a-fA-F]{32}');

class MdnsDiscovery {
  MdnsDiscovery({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  /// Returns the first Streamplayer found, or null if none appears before the
  /// timeout. Never hangs: a device that is off must produce a decision, not a
  /// spinner that lasts forever.
  Future<CastAddress?> findStreamplayer() async {
    try {
      return await MulticastLock.hold(_browse).timeout(timeout, onTimeout: () => null);
    } on SocketException {
      // No network, or the platform refused the multicast socket. Indis-
      // tinguishable from "not found" as far as the caller is concerned.
      return null;
    }
  }

  Future<CastAddress?> _browse() async {
    final client = MDnsClient();
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
    try {
      await for (final txt in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(instance),
      )) {
        for (final line in txt.text.split('\n')) {
          if (line.startsWith('fn=')) {
            final name = line.substring(3).trim();
            if (name.isNotEmpty) return name;
          }
        }
      }
    } on Exception {
      // TXT is a nicety; never let it fail the discovery.
    }
    return null;
  }

  String _instanceLabel(String instance) =>
      instance.split('.').first.replaceAll(RegExp(r'-[0-9a-fA-F]{32}$'), '');
}
