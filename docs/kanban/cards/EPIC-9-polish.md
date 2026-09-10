# EPIC-9 — Polish and release

---

## POL-01 — Wall-display mode

**As** the office, **I want** an old tablet on the wall showing the track permanently,
**so that** nobody has to pull out a phone.

**Acceptance**
- [ ] A mode that keeps the screen awake and hides all chrome.
- [ ] Large-format layout tuned for viewing across the room.
- [ ] Optional dimming when `Idle`, so it isn't a nightlight.
- [ ] Runs for days without a memory or handle leak.

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
