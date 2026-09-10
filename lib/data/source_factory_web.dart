/// Web source construction.
///
/// Browsers cannot open the raw TLS socket CASTV2 needs, so the relay is the
/// only option — and no configuration is required, because the page was served
/// by the relay and can derive the socket URL from its own origin.
library;

import '../config/app_config.dart';
import '../domain/now_playing_source.dart';
import 'address_cache.dart';
import 'fake_source.dart';
import 'relay_source.dart';

/// [addressCache] is accepted only to match the io factory's signature, which
/// the conditional export requires. Nothing on web ever discovers a device
/// address, so there is nothing to cache.
NowPlayingSource createSource(
  AppConfig config, {
  AddressCache addressCache = const NoAddressCache(),
}) {
  // `?demo` runs the UI on scripted data with no relay and no speaker, so the
  // same bundle can be shown to people who are not on the office network —
  // and so the UI can be worked on anywhere. It is never selected by accident:
  // the parameter has to be in the URL.
  if (isDemo(Uri.base)) return FakeSource();
  return RelaySource(url: config.relayUrl ?? defaultRelayUrl());
}

/// True when the page URL asks for the scripted demo.
bool isDemo(Uri uri) {
  if (!uri.queryParameters.containsKey('demo')) return false;
  const off = {'0', 'false', 'off', 'no'};
  return !off.contains(uri.queryParameters['demo']!.toLowerCase());
}

String defaultRelayUrl() {
  final base = Uri.base;
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  final port = base.hasPort ? ':${base.port}' : '';
  return '$scheme://${base.host}$port/ws';
}
