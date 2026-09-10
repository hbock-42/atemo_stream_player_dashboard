/// Web source construction.
///
/// Browsers cannot open the raw TLS socket CASTV2 needs, so the relay is the
/// only option — and no configuration is required, because the page was served
/// by the relay and can derive the socket URL from its own origin.
library;

import '../config/app_config.dart';
import '../domain/now_playing_source.dart';
import 'relay_source.dart';

NowPlayingSource createSource(AppConfig config) =>
    RelaySource(url: config.relayUrl ?? defaultRelayUrl());

String defaultRelayUrl() {
  final base = Uri.base;
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  final port = base.hasPort ? ':${base.port}' : '';
  return '$scheme://${base.host}$port/ws';
}
