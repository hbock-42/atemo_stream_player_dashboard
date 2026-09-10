# EPIC-10 — Web target

**Goal:** the primary way people reach this. Open a URL on office Wi-Fi, see the track,
control the speaker, install nothing.

Decision: [ADR-0005](../../adr/0005-web-delivery-via-relay.md). Depends on the relay
(EPIC-7), which is what actually holds the Cast connection — a browser cannot.

---

## WEB-01 — Flutter Web build with `dart:io` excluded

**As** the developer, **I want** the app to compile for web, **so that** the browser target
is real rather than aspirational.

**Acceptance**
- [ ] `flutter build web` succeeds.
- [ ] `DirectCastSource`, `cast/` and `discovery/` are unreachable from the web entrypoint,
      via the conditional export in [CORE-04]. The web factory returns `RelaySource` only.
- [ ] No `dart:io` import is reachable from `main.dart` on web — a compile failure is the
      test, and CI ([TEST-04]) runs it on every push.
- [ ] The no-Material constraint holds identically on web: `WidgetsApp`, hand-built
      primitives, bundled font.
- [ ] Renders correctly in Chrome, Safari and Firefox, on desktop and mobile.
- [ ] First load over the LAN is acceptable. CanvasKit's payload is a few MB; measure it and
      note the number rather than being surprised by it.

**Size:** M

---

## WEB-02 — Zero-config relay URL from page origin

**As** a colleague, **I want** to type nothing, **so that** opening the bookmark just works.

**Acceptance**
- [ ] On web, the relay WebSocket URL is derived from the page's own origin
      (`ws://${location.host}/ws`) — the relay served the page, so it knows where the relay
      is by construction.
- [ ] No mDNS, no manual IP, no settings screen on the web path.
- [ ] Works unchanged if the relay is later moved, renamed, or put behind a tunnel.
- [ ] The `wss://` case is handled for a future tunnelled deployment.

**Size:** S

---

## WEB-03 — Browser gotchas

**As** a user with the page open on a desk, **I want** it to keep working, **so that** it's
a display and not a thing I have to poke.

**Acceptance**
- [x] The WebSocket reconnects after a laptop sleeps or a phone locks; a browser tab left
      open overnight is showing live data in the morning. `RelaySource.reconnectNow()`,
      driven by `visibilitychange` / `pageshow` / `online` through `lib/platform/browser.dart`:
      backoff is right for a relay that is down and wrong for a laptop that just woke.
- [x] Mobile Safari backgrounding a tab and returning does not leave stale state. A resume
      replaces the socket even when it still *looks* alive — a frozen tab comes back holding
      a socket that is dead at the far end and will never report `onDone` — and the relay
      sends current state on connect, so the reconnect is also the refresh.
- [x] Screen Wake Lock API used where available so a propped-up phone doesn't dim, with
      graceful absence where it isn't. Taken by the wall display ([POL-01], which any
      propped-up phone can enter with `?wall`); feature-detected, so an older Safari or
      Firefox simply does without. The remote deliberately does not hold your phone awake
      while it is in your hand.
- [x] No audio is ever played by the page, so no autoplay policy is ever engaged. Verified:
      there is no `<audio>`, `<video>` or `AudioContext` anywhere in `lib/` or `web/`, and
      every `play()` in the codebase is a command sent *to the speaker*. This is a remote
      and a display, not a player.
- [x] Layout works from a 360px phone up to a desktop browser. Tested at 360, 390, 768 and
      1440; content is capped at 520px and centred so text is not stretched across a
      monitor. `index.html` now carries the `width=device-width` viewport meta without which
      mobile browsers would render at a 980px virtual width and every layout decision would
      be made against the wrong number.
- [x] Browser back/refresh behaves sanely on a single-screen app. There is one screen and no
      route is ever pushed (ADR-0003), so Back leaves the page rather than unwinding app
      state, and refresh is a clean reconnect that costs nothing: all state comes from the
      relay on connect and none of it is local.

**Size:** M

---

## WEB-04 — Add-to-home-screen

**As** a colleague, **I want** it on my home screen, **so that** it feels like an app without
being one.

**Acceptance**
- [x] `manifest.json` with name, icons, `display: standalone`, theme colour matching
      [CORE-03]'s palette — `#0E0E11`, the same literal as `AppColors.dark.background`, so
      chrome, launch screen and app are one colour and there is no white flash. Icons are
      the app's own note glyph in the palette's accent, in plain and maskable variants.
- [x] Adding to the home screen on Android and iOS opens without browser chrome:
      `display: standalone` plus both the modern `mobile-web-app-capable` and the
      `apple-` prefixed meta tag iOS still reads.
- [x] Does most of what [POL-02] was for, at a fraction of the cost.
- [x] No service worker caching of application state. `web/flutter_bootstrap.js` calls
      `_flutter.loader.load()` with no `serviceWorkerSettings` — that absence *is* the
      mechanism, which is why the file exists to say so — and unregisters any worker an
      earlier deploy left behind, so the people who visited first are not the ones stuck on
      a stale bundle.

**Size:** S
