# EPIC-5 — UI

**Goal:** four states, legible across a room, built from `widgets.dart` only.

Constraint: [ADR-0003](../../adr/0003-no-material-cupertino.md). No `material.dart`, no
`cupertino.dart`, no UI package. Every screen is developable against `FakeSource`.

---

## UI-01 — Now-playing screen

**As** anyone in the office, **I want** to see what's playing, **so that** I can find out
what this track is without asking.

**Acceptance**
- [ ] Shows artwork, title, artist, album, play/pause state, casting app.
- [ ] Title truncates gracefully at two lines; artist at one.
- [ ] Readable from ~3 metres — title large and high contrast.
- [ ] Portrait and landscape; phone and tablet widths.
- [ ] Paused is visually distinct from playing at a glance.
- [ ] Rebuilds only on actual change ([DOM-01] equality).
- [ ] Imports only `package:flutter/widgets.dart` and `ui/`.

**Size:** M

---

## UI-02 — Idle state

**As** a user, **I want** to see clearly that the speaker is on but silent, **so that** I
don't think the app is broken.

**Acceptance**
- [ ] Distinct from `Unreachable` in wording and visuals — this is the point of the card.
- [ ] Names the device ("Streamplayer — nothing playing").
- [ ] No stale artwork or track from the previous session.
- [ ] Reached both by app-quit and by `playerState == IDLE`.

**Size:** S

---

## UI-03 — Unreachable state

**As** a user, **I want** to know the speaker can't be reached and be able to retry,
**so that** I can tell a network problem from silence.

**Acceptance**
- [ ] Clearly different from `Idle`.
- [ ] Shows the reason: not found on the network, connection lost, or local network
      permission denied (iOS, per [DISC-03]).
- [ ] A retry control ([CORE-03] `AppButton`) calling the controller's retry.
- [ ] Indicates that automatic retry is already happening, so retry is a shortcut, not a
      requirement.

**Size:** S

---

## UI-04 — Artwork

**Acceptance**
- [ ] Loads from the URL in the media status with a loading state.
- [ ] Handles device-local `http://` artwork URLs — Android 9+ cleartext policy must be
      configured narrowly (a `network_security_config.xml` permitting the device subnet),
      not by enabling cleartext globally.
- [ ] Missing, broken or slow artwork falls back to a designed placeholder, never a broken
      image or an exception.
- [ ] Artwork does not flicker when the same URL arrives in successive status messages.
- [ ] Aspect ratio preserved; no layout jump between having and not having artwork.

**Size:** M

---

## UI-05 — Casting-app attribution

**As** a user, **I want** to see whether this is Spotify or Tidal, **so that** I know where
to go to find the track.

**Acceptance**
- [ ] Shows the `displayName` from the receiver status.
- [ ] Unknown or absent app names degrade to hiding the element, not to "null".
- [ ] Verified against whatever [SPIKE-01] found for each service.

**Size:** S

---

## UI-06 — Transitions

**Acceptance**
- [ ] State changes cross-fade rather than snapping.
- [ ] Track changes within `Playing` animate the text/artwork swap.
- [ ] Brief `Connecting` flickers (< 500ms) are suppressed so a fast reconnect isn't visible
      as a flash.
- [ ] Animations built from `AnimatedOpacity`/`AnimatedSwitcher` — plain `widgets.dart`.

**Size:** S

---

## UI-07 — Transport controls, capability-gated

**As** a user, **I want** to pause and skip from the page, **so that** I don't have to track
down whoever's phone is casting.

**Acceptance**
- [ ] Play/pause, previous, next rendered from [CORE-03] primitives.
- [ ] Each control's enabled state comes from `Playing.capabilities`, never from a guess.
      An app that doesn't support skipping shows disabled skip buttons, not buttons that
      do nothing.
- [ ] Play/pause reflects the optimistic state from [STATE-02] immediately on tap.
- [ ] A reverted command is visible as the button returning to its prior state, not as a
      silent no-op.
- [ ] Touch targets at least 44pt — this is used one-handed, across a room, in a hurry.
- [ ] No `STOP` control anywhere. Deliberate; see [ADR-0004](../../adr/0004-bidirectional-control.md).

**Size:** M

---

## UI-08 — Volume slider and mute

**As** a user, **I want** to turn the music down without getting up, **so that** I can take
a call.

**Acceptance**
- [ ] `AppSlider` bound to device volume, with a mute toggle.
- [ ] Available in **both** `Playing` and `Idle` — device volume is app-independent and is
      the one control guaranteed to work ([OQ-5](../../open-questions.md#oq-5--will-the-device-accept-commands-from-a-sender-that-did-not-launch-the-session)).
- [ ] Dragging is smooth: local state leads, outbound messages are rate-limited by
      [CAST-07], inbound updates are suppressed mid-drag by [STATE-02].
- [ ] The final position is always transmitted, even if the last movement was inside the
      rate-limit window.
- [ ] Mute reflects and round-trips the device's real muted flag.
- [ ] Consider a maximum-volume clamp — this is an office and the slider is public. Decide
      with the user; default is no clamp.

**Size:** M

---

## UI-09 — Read-only mode

**As** a user on a client without control rights, **I want** to understand why I can't press
anything, **so that** I don't think the app is broken.

**Acceptance**
- [ ] When `source.control == null`, controls are hidden entirely rather than shown disabled
      — this is a different situation from an app that lacks a capability, and should look
      different.
- [ ] A quiet line explains it ("view only").
- [ ] Reachable states: a Spotify source lacking the modify scope, and a relay client
      refused control by [RELAY-05]'s address or origin checks. Under
      [ADR-0006](../../adr/0006-lan-membership-is-the-auth-boundary.md) a normal office
      client always gets control, so this is an edge state — but a real one, and viewing
      stays available when control is refused.
- [ ] Developable against `FakeSource(control: null)`.

**Size:** S
