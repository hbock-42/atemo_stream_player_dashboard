/// Web source construction.
///
/// Browsers cannot open the raw TLS socket CASTV2 needs, so the relay is the
/// only option — and no configuration is required, because the page was served
/// by the relay and can derive the socket URL from its own origin.
library;

import '../config/app_config.dart';
import '../domain/now_playing_source.dart';
import 'address_cache.dart';
import 'relay_source.dart';

/// [addressCache] is accepted only to match the io factory's signature, which
/// the conditional export requires. Nothing on web ever discovers a device
/// address, so there is nothing to cache.
NowPlayingSource createSource(
  AppConfig config, {
  AddressCache addressCache = const NoAddressCache(),
}) =>
    RelaySource(url: config.relayUrl ?? defaultRelayUrl());

String defaultRelayUrl() {
  final base = Uri.base;
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  final port = base.hasPort ? ':${base.port}' : '';
  return '$scheme://${base.host}$port/ws';
}
