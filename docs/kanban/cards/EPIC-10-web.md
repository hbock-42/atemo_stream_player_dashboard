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
- [ ] The WebSocket reconnects after a laptop sleeps or a phone locks; a browser tab left
      open overnight is showing live data in the morning.
- [ ] Mobile Safari backgrounding a tab and returning does not leave stale state.
- [ ] Screen Wake Lock API used where available so a propped-up phone doesn't dim, with
      graceful absence where it isn't.
- [ ] No audio is ever played by the page, so no autoplay policy is ever engaged. Worth
      stating explicitly: this is a remote and a display, not a player.
- [ ] Layout works from a 360px phone up to a desktop browser.
- [ ] Browser back/refresh behaves sanely on a single-screen app.

**Size:** M

---

## WEB-04 — Add-to-home-screen

**As** a colleague, **I want** it on my home screen, **so that** it feels like an app without
being one.

**Acceptance**
- [ ] `manifest.json` with name, icons, `display: standalone`, theme colour matching
      [CORE-03]'s palette.
- [ ] Adding to the home screen on Android and iOS opens without browser chrome.
- [ ] Does most of what [POL-02] was for, at a fraction of the cost.
- [ ] No service worker caching of application state — the page must always reflect the live
      relay, and a stale cached bundle after a redeploy is a support call nobody wants.

**Size:** S
