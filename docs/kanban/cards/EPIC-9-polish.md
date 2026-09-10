# EPIC-9 — Polish and release

---

## POL-01 — Wall-display mode

**As** the office, **I want** an old tablet on the wall showing the track permanently,
**so that** nobody has to pull out a phone.

**Acceptance**
- [x] A mode that keeps the screen awake and hides all chrome. Screen Wake Lock on web,
      feature-detected so an older tablet degrades to its own "screen timeout: never"
      instead of failing. No native wakelock plugin is added — that would be a new
      dependency for the non-primary target; recorded as a native follow-up in
      `lib/platform/browser_stub.dart`. Chrome is not hidden so much as absent: the wall is
      a separate widget with nothing tappable on it.
- [x] Large-format layout tuned for viewing across the room. Type and artwork are sized from
      the viewport rather than from the phone-tuned token scale, and the layout goes side by
      side on a landscape tablet and stacked in portrait.
- [x] Optional dimming when `Idle`, so it isn't a nightlight — dimmed to 28% rather than
      blanked, because a black wall reads as "broken".
- [x] Runs for days without a memory or handle leak: no timers at all, exactly one listener
      (the browser bridge) cancelled on dispose, and artwork keyed on its URL so an
      unchanged track never re-fetches. Covered by a test that drives 200 state changes
      across a simulated 100 minutes and asserts no pending timers and one wake-lock
      acquisition.

**How the mode is entered:** by URL — `http://streamplayer.local:8080/?wall`. The relay
already serves the page, so the flag rides along on the bookmark the tablet is set up with
once; there is nothing to persist, no settings screen, and no gesture a passer-by can
trigger by accident. `?wall=0` turns it off again. `Uri.base` is the page URL on web and a
`file:` path on native, so the native build never sees the flag. See
`lib/ui/widgets/display_mode.dart`.

**Size:** S

---

## POL-02 — Native builds for people who want an icon

**Much smaller than it was.** [ADR-0005](../../adr/0005-web-delivery-via-relay.md) makes the
browser the primary way in, so nobody *has* to install anything — [WEB-04]'s
add-to-home-screen covers most of what an app icon was for. This card is now optional
polish, not a release blocker.

**As** someone who wants it on their home screen as a real app, **I want** a native build,
**so that** it behaves like one.

**Acceptance**
- [ ] Android: a signed APK plus a one-line install instruction.
- [ ] iOS: a documented route (TestFlight or ad-hoc), with its device-count limits stated
      honestly up front — and a note that the web UI avoids all of this.
- [ ] App icon and name.
- [ ] Native builds default to the relay, falling back to direct if it's unreachable.

**Size:** S

---

## POL-03 — Diagnostics screen

**As** the developer, **I want** to see connection state on someone else's phone,
**so that** "it doesn't work" becomes a fixable report.

**Acceptance**
- [ ] Hidden entry point (long-press).
- [ ] Shows discovered address, connection state, last error, current `transportId`,
      seconds since last message, source mode.
- [ ] A recent log buffer that can be copied to the clipboard.
- [ ] Contains nothing sensitive; safe to leave in release builds.

**Size:** S
