/// App entry point.
///
/// Rooted at [WidgetsApp], not MaterialApp: no material.dart, no
/// cupertino.dart anywhere in this project (ADR-0003). That means text style,
/// text direction, background and safe areas are all supplied explicitly.
library;

import 'package:flutter/widgets.dart';

import 'config/app_config.dart';
import 'data/source_factory.dart';
import 'state/now_playing_controller.dart';
import 'ui/screens/diagnostics_gate.dart';
import 'ui/screens/now_playing_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StreamplayerApp());
}

class StreamplayerApp extends StatefulWidget {
  const StreamplayerApp({super.key, this.config = const AppConfig()});

  final AppConfig config;

  @override
  State<StreamplayerApp> createState() => _StreamplayerAppState();
}

class _StreamplayerAppState extends State<StreamplayerApp> {
  late final NowPlayingController _controller = NowPlayingController(
    createSource: () => createSource(widget.config),
  );

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
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
