/// Native source construction. Can connect directly to the device or through
/// the relay.
library;

import 'dart:async';

import '../cast/cast_client.dart';
import '../config/app_config.dart';
import '../discovery/mdns_discovery.dart';
import '../domain/now_playing_source.dart';
import 'address_cache.dart';
import 'cached_address_resolver.dart';
import 'direct_cast_source.dart';
import 'relay_source.dart';

/// [addressCache] persists the last address that worked, so a cold start can
/// skip mDNS (DISC-04). Pass `ConfigStore().addressCache` from the app; the
/// default keeps this callable from tests and from the relay, which has no
/// Flutter and no need for the cache.
NowPlayingSource createSource(
  AppConfig config, {
  AddressCache addressCache = const NoAddressCache(),
}) {
  if (config.mode == SourceMode.relay && config.relayUrl != null) {
    return RelaySource(url: config.relayUrl!);
  }

  final discovery = MdnsDiscovery();
  final resolver = CachedAddressResolver(
    cache: addressCache,
    discover: discovery.findStreamplayer,
    // An explicit host wins over everything: it exists for networks where
    // multicast is blocked and discovery can never succeed.
    manualHost: config.manualHost,
  );

  final source = DirectCastSource(resolveAddress: resolver.resolve);
  // A snapshot means the handshake completed, which is the only evidence that
  // an address is worth remembering. Discovery returning something is not:
  // the device may still refuse the socket.
  source.client.updates.listen((update) {
    if (update is CastSnapshotUpdate) unawaited(resolver.markConnected());
  });
  return source;
}
