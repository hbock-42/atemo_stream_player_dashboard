# EPIC-7 — Relay topology

**Goal:** one CASTV2 connection to the device, N browsers watching and controlling. The
relay both fans out state and serves the web UI.

**Now mandatory and in M1.** Browsers cannot open the raw TLS socket CASTV2 requires, so a
browser-delivered UI is impossible without a LAN process holding the connection on its
behalf — [ADR-0005](../../adr/0005-web-delivery-via-relay.md). This also answers
[OQ-2](../../open-questions.md#oq-2--how-many-concurrent-castv2-senders-does-the-device-tolerate)
by construction.

Decision: [ADR-0002](../../adr/0002-direct-then-relay.md), amended by ADR-0005.

**The key property:** the relay is not a rewrite. It runs `lib/cast/` unchanged, which is
why that code carries no Flutter import.

---

## RELAY-01 — Headless relay server

**Acceptance**
- [ ] A `dart:io` console app in `relay/` depending on the shared `cast/` and `domain/`
      code — no duplicated protocol logic.
- [ ] Discovers and connects to the device, holds exactly one connection, applies the same
      reconnect policy as [CAST-06].
- [ ] Runs for a week without intervention (soak).
- [ ] Structured logging so a failure at 3am is diagnosable afterwards.

**Size:** M

---

## RELAY-02 — WebSocket fan-out

**Acceptance**
- [ ] A WebSocket endpoint serving `NowPlaying` as JSON ([DOM-01] `toJson`) — the domain
      model, never raw Cast payloads.
- [ ] Latest state is sent immediately on connect, then on every change.
- [ ] A client connecting, disconnecting, or dying does not affect the device connection or
      other clients.
- [ ] Tested with 20 simultaneous clients.
- [ ] Advertises itself over mDNS so the app finds the relay without configuration.

**Size:** M

---

## RELAY-03 — `RelaySource`

**Acceptance**
- [ ] Implements `NowPlayingSource` over the WebSocket; deserialises to the same
      `NowPlaying` types.
- [ ] Reconnects to the relay with backoff; a relay restart is invisible to the user.
- [ ] Relay unreachable ⇒ `Unreachable` with a reason naming the relay, distinct from the
      device being unreachable.
- [ ] Swapping `direct` ⇄ `relay` in [CORE-04] changes nothing in `ui/` — verified by the
      diff.

**Size:** S

---

## RELAY-04 — Deployment, stable hostname, runbook

**As** the office, **I want** a URL that works every day, **so that** the bookmark doesn't
rot.

The relay is now a single point of failure for everyone. This card is why that's acceptable.

**Acceptance**
- [ ] Runs as a service that survives reboot on the chosen host, unattended.
- [ ] A memorable address that resolves from real handsets. Resolves
      [OQ-7](../../open-questions.md#oq-7--does-the-relay-host-have-a-stable-name-on-the-office-network):
      test `http://streamplayer.local:8080` from Android and iOS, and fall back to a static
      IP if mDNS resolution is unreliable.
- [ ] A one-page runbook: install, start, stop, read logs, what to check when the office
      says "the page is stuck".
- [ ] Health endpoint reporting device connection state, client count, and uptime.
- [ ] Structured logs survive restart, so a 3am failure is diagnosable in the morning.

**Size:** M

---

## RELAY-05 — Inbound command channel and authorisation hook

**As** a user, **I want** the buttons on the web page to actually control the speaker,
**so that** the web UI is a remote and not just a display.

Depends on [CAST-07]. Policy: [OQ-6](../../open-questions.md#oq-6--who-is-allowed-to-control-the-speaker).

**Acceptance**
- [ ] The WebSocket carries client→relay command messages in a small typed envelope,
      mapping onto `PlaybackControl`.
- [ ] The relay validates and rate-limits commands before forwarding, so one misbehaving
      browser tab cannot flood the device.
- [ ] Volume commands from multiple clients are coalesced sanely rather than fighting.
- [ ] Command results and the resulting status broadcast to **all** clients, so two people
      looking at the page see the same thing.
- [ ] An authorisation hook exists as a single injection point — one function that decides
      whether a client may command — defaulting to "everyone may", pending the user's
      answer on OQ-6. Unauthorised clients receive `control: null` at connect, which [UI-09]
      already renders.
- [ ] `LAUNCH`/`LOAD` are unrepresentable in the envelope, not merely rejected.

**Size:** M

---

## RELAY-06 — Serve the Flutter Web bundle

**As** a colleague, **I want** to open a URL and see the player, **so that** I don't install
anything.

**Acceptance**
- [ ] The relay serves the `flutter build web` output over HTTP on the same host and port
      as the WebSocket, so [WEB-02]'s origin-derived URL works with no configuration.
- [ ] Correct MIME types and caching headers; a redeploy is picked up without users having
      to hard-refresh.
- [ ] Serving static files never blocks or delays the Cast connection or the fan-out.
- [ ] Verified end to end: a phone that has never seen the app opens the URL on office
      Wi-Fi and sees the live track within a couple of seconds.

**Size:** S
