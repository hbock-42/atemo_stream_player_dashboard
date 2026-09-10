/// Web: the real browser signals, via `package:web`.
///
/// `package:web` ships with the Flutter web SDK, so this costs no pub
/// dependency — and it is the supported successor to `dart:html`, which is
/// deprecated and unavailable under Wasm.
///
/// Everything here is registered once and removed in [dispose]: a wall display
/// runs for days, and a listener added per rebuild would be a slow leak.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

import 'browser_bridge.dart';

BrowserBridge createBrowserBridge() => WebBrowserBridge();

class WebBrowserBridge implements BrowserBridge {
  WebBrowserBridge() {
    _onVisibility = _resume.toJS;
    _onOnline = _resume.toJS;
    _onPageShow = _resume.toJS;

    // visibilitychange covers a phone locking and unlocking and a laptop tab
    // being switched away from; pageshow covers Safari restoring the page from
    // the back/forward cache, which fires no visibilitychange at all; online
    // covers Wi-Fi dropping and returning without the tab ever hiding.
    web.document.addEventListener('visibilitychange', _onVisibility);
    web.window.addEventListener('pageshow', _onPageShow);
    web.window.addEventListener('online', _onOnline);
  }

  final StreamController<void> _controller = StreamController<void>.broadcast();

  late final web.EventListener _onVisibility;
  late final web.EventListener _onOnline;
  late final web.EventListener _onPageShow;

  bool _keepAwake = false;
  bool _disposed = false;
  web.WakeLockSentinel? _sentinel;

  @override
  Stream<void> get resumed => _controller.stream;

  @override
  bool get isVisible => web.document.visibilityState != 'hidden';

  /// Feature detection rather than a browser sniff: iOS Safari gained this in
  /// 16.4 and the office tablet may well be older.
  @override
  bool get canKeepAwake => web.window.navigator.has('wakeLock');

  void _resume(web.Event event) {
    if (_disposed || !isVisible) return;
    // Browsers release the wake lock whenever the page is hidden and never
    // give it back on their own.
    if (_keepAwake) unawaited(_acquire());
    if (!_controller.isClosed) _controller.add(null);
  }

  @override
  Future<void> setKeepAwake(bool enabled) async {
    if (_keepAwake == enabled) return;
    _keepAwake = enabled;
    if (enabled) {
      await _acquire();
    } else {
      await _release();
    }
  }

  Future<void> _acquire() async {
    if (!canKeepAwake || _sentinel != null || !isVisible) return;
    try {
      _sentinel = await web.window.navigator.wakeLock.request('screen').toDart;
      // Disposed while the promise was in flight.
      if (_disposed || !_keepAwake) await _release();
    } on Object {
      // A wake lock is a nicety: denied by policy, refused on battery saver,
      // or simply absent. The display keeps working, the screen may dim.
      _sentinel = null;
    }
  }

  Future<void> _release() async {
    final sentinel = _sentinel;
    _sentinel = null;
    if (sentinel == null) return;
    try {
      await sentinel.release().toDart;
    } on Object {
      // Already released by the platform.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _keepAwake = false;
    web.document.removeEventListener('visibilitychange', _onVisibility);
    web.window.removeEventListener('pageshow', _onPageShow);
    web.window.removeEventListener('online', _onOnline);
    unawaited(_release());
    unawaited(_controller.close());
  }
}
