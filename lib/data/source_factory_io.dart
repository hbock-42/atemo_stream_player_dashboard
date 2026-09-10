/// Native source construction. Can connect directly to the device or through
/// the relay.
library;

import '../cast/cast_address.dart';
import '../config/app_config.dart';
import '../discovery/mdns_discovery.dart';
import '../domain/now_playing_source.dart';
import 'direct_cast_source.dart';
import 'relay_source.dart';

NowPlayingSource createSource(AppConfig config) {
  if (config.mode == SourceMode.relay && config.relayUrl != null) {
    return RelaySource(url: config.relayUrl!);
  }

  final discovery = MdnsDiscovery();
  CastAddress? cached;

  return DirectCastSource(
    resolveAddress: ({bool forceRefresh = false}) async {
      // An explicit host wins over everything: it exists for networks where
      // multicast is blocked and discovery can never succeed.
      final manualHost = config.manualHost;
      if (manualHost != null && manualHost.isNotEmpty) {
        return CastAddress(host: manualHost, friendlyName: 'Streamplayer');
      }
      if (!forceRefresh && cached != null) return cached;
      cached = await discovery.findStreamplayer();
      return cached;
    },
  );
}
