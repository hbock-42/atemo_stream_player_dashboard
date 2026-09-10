/// Builds the right source for the platform.
///
/// The conditional export is what keeps `dart:io` — and therefore the whole
/// CASTV2 client — out of the web bundle. A browser cannot open a raw TLS
/// socket, so on web the only possible source is the relay. See ADR-0005.
///
/// The app ships to browsers only (ADR-0007), so the io branch is reached by
/// `flutter test` on the Dart VM and by the relay, which runs the same
/// `DirectCastSource` headless. It is not dead code.
library;

export 'source_factory_io.dart' if (dart.library.js_interop) 'source_factory_web.dart';
