/// A browser bridge the test drives by hand: no browser, no timing luck.
library;

import 'dart:async';

import 'package:atemo_stream_player_viewer/platform/browser.dart';

class FakeBrowser implements BrowserBridge {
  FakeBrowser({this.canKeepAwake = true});

  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  final bool canKeepAwake;

  @override
  bool isVisible = true;

  bool keepAwake = false;
  int keepAwakeCalls = 0;
  bool disposed = false;

  /// True while something is subscribed to [resumed] — a leaked listener is
  /// the failure mode a wall display would hit after a week.
  bool get hasListener => _controller.hasListener;

  @override
  Stream<void> get resumed => _controller.stream;

  /// The laptop woke up / the tab came back / Wi-Fi returned.
  void resume() => _controller.add(null);

  @override
  Future<void> setKeepAwake(bool enabled) async {
    keepAwakeCalls++;
    keepAwake = enabled;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_controller.close());
  }
}
