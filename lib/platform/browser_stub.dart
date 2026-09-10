/// Native: there is no browser, so every browser signal is inert.
///
/// The native equivalents are real work and deliberately out of scope: keeping
/// an Android/iOS screen awake needs a plugin (`wakelock_plus` or a platform
/// channel), and this project does not add a dependency without a written
/// reason. Recorded as a native follow-up on POL-01 instead — a native wall
/// display can set the tablet's own screen timeout to "never" today, and the
/// wall display's primary delivery is the browser anyway (ADR-0005).
///
/// Native lifecycle (app backgrounded/resumed) is already handled by
/// `NowPlayingController`'s `WidgetsBindingObserver`; this bridge exists for
/// the browser-only half that Flutter does not surface.
library;

import 'browser_bridge.dart';

BrowserBridge createBrowserBridge() => InertBrowserBridge();
