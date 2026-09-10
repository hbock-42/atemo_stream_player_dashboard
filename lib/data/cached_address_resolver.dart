/// Resolves the device address quickly on a cold start (DISC-04).
///
/// The point of this class is the race. mDNS costs up to five seconds, and on
/// most launches the device is exactly where it was last time — so discovery
/// is *started* first and the cached address is returned without waiting for
/// it. If the cache is right we never pay for mDNS at all; if it is wrong the
/// connection fails, `CastClient` asks again with `forceRefresh: true`, and the
/// browse that has been running in the background answers immediately.
library;

import 'dart:async';

import '../cast/cast_address.dart';
import 'address_cache.dart';

/// Discovery, as this resolver needs it: one shot, null when nothing is found.
typedef DiscoverAddress = Future<CastAddress?> Function();

class CachedAddressResolver {
  CachedAddressResolver({
    required AddressCache cache,
    required DiscoverAddress discover,
    this.manualHost,
    this.manualLabel = 'Streamplayer',
  })  : _cache = cache,
        _discover = discover;

  final AddressCache _cache;
  final DiscoverAddress _discover;

  /// From `AppConfig`. Set on networks where multicast is blocked, and it wins
  /// over both the cache and discovery — it exists precisely because the other
  /// two cannot work there.
  final String? manualHost;

  final String manualLabel;

  Future<CastAddress?>? _discovery;
  CastAddress? _handedOut;

  /// Matches `CastAddressResolver`; pass to `CastClient`/`DirectCastSource`.
  Future<CastAddress?> resolve({bool forceRefresh = false}) async {
    final manual = manualHost;
    if (manual != null && manual.isNotEmpty) {
      return _handedOut = CastAddress(host: manual, friendlyName: manualLabel);
    }

    if (forceRefresh) {
      // Three failed connections in a row: the address we hold is wrong, most
      // likely because DHCP moved the device. Drop it, and start a browse that
      // nothing stale can answer.
      _handedOut = null;
      _discovery = null;
      await _cache.clear();
    }

    // Started before the cache is consulted, so the two run in parallel.
    final discovery = _discovery ??= _startDiscovery();

    if (!forceRefresh) {
      final cached = await _cache.read();
      if (cached != null) return _handedOut = cached;
    }

    final found = await discovery;
    // Let the next resolve start a fresh browse rather than replay this one.
    _discovery = null;
    if (found != null) await _cache.write(found);
    return _handedOut = found;
  }

  /// Call when a connection to the address last handed out actually worked.
  /// That — not "discovery returned something" — is what makes an address
  /// worth remembering for the next cold start.
  Future<void> markConnected() async {
    final address = _handedOut;
    if (address == null) return;
    await _cache.write(address);
  }

  /// A browse whose failure is absorbed: nothing awaits this future on the
  /// fast path, and an unawaited error would surface as an unhandled async
  /// error and take the process down. "Refused by the platform" and "not
  /// found" are the same answer to the caller anyway.
  Future<CastAddress?> _startDiscovery() => _discover().then<CastAddress?>(
        (address) => address,
        onError: (Object _, StackTrace _) => null,
      );
}
