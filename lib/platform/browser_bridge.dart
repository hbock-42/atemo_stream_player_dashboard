/// The browser facts the rest of the app cares about, expressed so that native
/// builds can ignore them.
///
/// Two unrelated-looking needs share one seam because they share one source of
/// truth — "the page is in front of a human again":
///
///   * `RelaySource` wants to stop waiting out its backoff the moment the
///     laptop wakes or the phone unlocks (WEB-03);
///   * the wall display wants to re-take the screen wake lock, which browsers
///     drop on every visibility change (POL-01).
///
/// The web implementation sits behind a conditional import so nothing web-only
/// reaches the native build. See `browser.dart`.
library;

import 'dart:async';

abstract interface class BrowserBridge {
  /// Fires when the browser reports the page visible again, restored from the
  /// back/forward cache, or the network back online.
  ///
  /// Broadcast: several listeners (the relay client and the wall display) may
  /// subscribe to the same bridge.
  Stream<void> get resumed;

  /// False while the tab is backgrounded. Always true off web.
  bool get isVisible;

  /// Whether a screen wake lock is even possible here. False off web, and
  /// false in browsers without the Screen Wake Lock API — callers degrade
  /// instead of branching.
  bool get canKeepAwake;

  /// Holds the screen awake while true, re-taking the lock after every
  /// backgrounding. Silently does nothing where [canKeepAwake] is false.
  Future<void> setKeepAwake(bool enabled);

  void dispose();
}

/// Used on native, and by tests that do not care about any of this.
class InertBrowserBridge implements BrowserBridge {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get resumed => _controller.stream;

  @override
  bool get isVisible => true;

  @override
  bool get canKeepAwake => false;

  @override
  Future<void> setKeepAwake(bool enabled) async {}

  @override
  void dispose() => unawaited(_controller.close());
}
