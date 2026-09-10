/// Picks the browser bridge for the current target.
///
/// The conditional import is what keeps `package:web` — and every other
/// browser-only symbol — out of the Android/iOS build, exactly as
/// `source_factory.dart` keeps `dart:io` out of the web bundle (ADR-0005).
library;

export 'browser_bridge.dart';
export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
