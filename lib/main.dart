/// App entry point.
///
/// Rooted at [WidgetsApp], not MaterialApp: no material.dart, no
/// cupertino.dart anywhere in this project (ADR-0003). That means text style,
/// text direction, background and safe areas are all supplied explicitly.
library;

import 'package:flutter/widgets.dart';

import 'config/app_config_controller.dart';
import 'config/config_store.dart';
import 'data/address_cache.dart';
import 'data/reconfigurable_source.dart';
import 'data/source_factory.dart';
import 'state/now_playing_controller.dart';
import 'ui/screens/diagnostics_gate.dart';
import 'ui/screens/now_playing_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted config before the first frame, so a device that has not
  // moved is reachable immediately rather than after a discovery round trip.
  final store = ConfigStore();
  final config = AppConfigController(store: store);
  await config.load();

  runApp(StreamplayerApp(config: config, addressCache: store.addressCache));
}

class StreamplayerApp extends StatefulWidget {
  const StreamplayerApp({super.key, this.config, this.addressCache});

  /// Null in tests and previews, which then run on defaults with no storage.
  final AppConfigController? config;
  final AddressCache? addressCache;

  @override
  State<StreamplayerApp> createState() => _StreamplayerAppState();
}

class _StreamplayerAppState extends State<StreamplayerApp> {
  late final AppConfigController _config =
      widget.config ?? AppConfigController();
  late final AddressCache _addressCache =
      widget.addressCache ?? const NoAddressCache();

  late final NowPlayingController _controller = NowPlayingController(
    // ReconfigurableSource swaps the inner source when the mode changes, so
    // switching between direct and relay does not need an app restart.
    createSource: () => ReconfigurableSource(
      initial: _config.config,
      configs: _config.changes,
      build: (config) => createSource(config, addressCache: _addressCache),
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.config == null) _config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const theme = AppTheme(child: SizedBox.shrink());

    return WidgetsApp(
      title: 'Streamplayer',
      // Required by WidgetsApp; used by the OS task switcher.
      color: AppColors.dark.background,
      debugShowCheckedModeBanner: false,
      builder: (context, _) => AppTheme(
        colors: theme.colors,
        typography: theme.typography,
        // Without an explicit DefaultTextStyle carrying a colour, text renders
        // with the yellow-on-red debug underline: there is no Material
        // ancestor to supply one.
        child: DefaultTextStyle(
          style: theme.typography.body,
          child: Directionality(
            textDirection: TextDirection.ltr,
            // Wrapped here rather than inside the screen: the diagnostics
            // entry point is an app-level concern, and NowPlayingScreen stays
            // unaware that it exists.
            child: DiagnosticsGate(
              read: () => _controller.diagnostics,
              child: NowPlayingScreen(controller: _controller),
            ),
          ),
        ),
      ),
    );
  }
}
