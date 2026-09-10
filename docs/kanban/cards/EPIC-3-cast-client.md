# EPIC-3 — CASTV2 client

**Goal:** a pure-Dart, Flutter-free client that connects to the device, follows whatever
session is running, and survives the device misbehaving.

Reference: [protocol.md](../../protocol.md). Decision: [ADR-0001](../../adr/0001-hand-rolled-castv2.md).

---

## CAST-01 — `CastMessage` protobuf

**Acceptance**
- [ ] `cast_channel.proto` vendored into the repo with its provenance noted.
- [ ] `cast_message.pb.dart` generated and checked in; `protoc` is not part of the build.
- [ ] A `tool/generate_proto.sh` documents how to regenerate.
- [ ] Round-trip test: encode a message, decode it, fields match.

**Size:** S

---

## CAST-02 — `CastChannel` — TLS and framing

**As** the client, **I want** a byte-level channel that yields whole `CastMessage`s,
**so that** the layers above never think about TCP.

**Acceptance**
- [ ] `SecureSocket.connect(ip, 8009)` with `onBadCertificate: (_) => true` — self-signed
      cert accepted deliberately and commented as such.
- [ ] Outgoing: 4-byte big-endian length prefix + serialised protobuf.
- [ ] Incoming: a buffer that emits a frame only when `buffer.length >= 4 + prefix`.
- [ ] Test-proven: two frames in one TCP read are both emitted; one frame split across
      three reads is emitted once, intact.
- [ ] Exposes `Stream<CastMessage>`, `send()`, `close()`; surfaces socket errors as stream
      errors rather than swallowing them.
- [ ] Connect timeout (5s) so a powered-off device fails fast.
- [ ] No `package:flutter` import.

**Size:** M

---

## CAST-03 — Handshake

**As** the client, **I want** to attach to the session already running, **so that** I can
read metadata without disturbing playback.

**Acceptance**
- [ ] Steps 2–5 of [protocol.md](../../protocol.md#handshake) implemented in order.
- [ ] Monotonic `requestId` correlates responses to requests.
- [ ] `sessionId`, `transportId`, `displayName`, `appId` extracted from `RECEIVER_STATUS`.
- [ ] Subsequent unprompted `MEDIA_STATUS` messages are emitted — **no polling**.
- [ ] Asserted in review: the client contains no `LAUNCH` and no `LOAD`. Other commands
      live in [CAST-07] and must not leak into the handshake path.
- [ ] `mediaSessionId` is tracked from every `MEDIA_STATUS` and exposed, since [CAST-07]
      needs it for every transport command.
- [ ] Handshake against the real device yields a real track.

**Size:** M

---

## CAST-04 — Heartbeat and liveness

**Acceptance**
- [ ] Every inbound `PING` is answered with `PONG` on the heartbeat namespace.
- [ ] An outbound `PING` on a 5s timer as a liveness probe.
- [ ] No inbound traffic of any kind for 15s ⇒ treat the socket as dead and tear down.
- [ ] Timers are cancelled on close; verified no timer leak across many reconnects.
- [ ] Soak test: connection survives 30 minutes idle against the real device.

**Size:** S

---

## CAST-05 — App change, app quit, Backdrop

**As** a user, **I want** the app to keep up when someone switches from Spotify to Tidal,
**so that** I don't see a stale track.

**Acceptance**
- [ ] A `RECEIVER_STATUS` with a different `transportId` closes the old virtual connection
      and redoes handshake steps 4–5 against the new one.
- [ ] `RECEIVER_STATUS` with no applications, or `displayName == "Backdrop"`, emits idle.
- [ ] `playerState == IDLE` emits idle without dropping the socket.
- [ ] Switching apps on the real device is reflected within ~2 seconds.
- [ ] Stale-metadata check: after a quit, the previous track is not still displayed.

**Size:** M

---

## CAST-06 — Reconnect

**As** a user, **I want** the app to recover on its own after the speaker is unplugged and
plugged back in, **so that** nobody has to restart anything.

**Acceptance**
- [ ] Backoff 1, 2, 4, 8, 16, 30s cap, with jitter; reset on successful handshake.
- [ ] Reconnect triggers on socket error, socket done, and liveness timeout.
- [ ] After three consecutive failures, discovery re-runs instead of reusing the address.
- [ ] Emits `Unreachable` while disconnected and recovers to `Playing`/`Idle` without user
      action.
- [ ] Verified by physically power-cycling the device.
- [ ] Verified by moving the phone off Wi-Fi and back.
- [ ] No unbounded reconnect loop, no overlapping reconnect attempts.

**Size:** M

---

## CAST-07 — `CastCommands` — volume, transport, capability gating

**As** a user, **I want** to pause the music and change the volume from the page, **so that**
I don't have to find whoever's phone is casting.

Decision: [ADR-0004](../../adr/0004-bidirectional-control.md). Wire format:
[protocol.md](../../protocol.md#commands-we-send). Gated by [SPIKE-04]'s findings.

**Acceptance**
- [ ] `SET_VOLUME {level}` and `{muted}` on the receiver namespace to `receiver-0`. Works
      with no app running — asserted by a test against the real device while idle.
- [ ] `PAUSE`, `PLAY`, `QUEUE_NEXT`, `QUEUE_PREV`, `SEEK` on the media namespace to the
      current `transportId`, each carrying the current `mediaSessionId`.
- [ ] A command issued with no current `mediaSessionId` is dropped client-side, not sent.
- [ ] `supportedMediaCommands` decoded into a `Capabilities` value object; every transport
      command checks it and refuses rather than firing blind.
- [ ] Volume changes are rate-limited to ~1 message per 100ms so a dragged slider does not
      flood the device; the final position is always sent.
- [ ] `STOP` implemented but not exported to the UI layer.
- [ ] **No `LAUNCH`, no `LOAD`** — enforced by [TEST-03], not just by review.
- [ ] Rejected or ignored commands are surfaced to the caller so [STATE-02] can revert.
- [ ] Verified against the real device: pause, resume, skip, and a volume sweep, while
      another phone is casting.

**Size:** M
