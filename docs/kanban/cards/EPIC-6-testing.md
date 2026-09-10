# EPIC-6 — Testing and tooling

**Goal:** we own the protocol ([ADR-0001](../../adr/0001-hand-rolled-castv2.md)), so we owe
ourselves the ability to test it without the device in the room.

---

## TEST-01 — Fake CASTV2 device

**As** the developer, **I want** a local fake receiver, **so that** protocol work doesn't
require being in the office with music playing.

**Acceptance**
- [ ] A `SecureServerSocket` with a self-signed test cert, speaking the same framing.
- [ ] Responds to `CONNECT`, `GET_STATUS` (receiver and media), and sends `PING`.
- [ ] Replays the fixtures captured in [SPIKE-01].
- [ ] Scriptable failure modes: abrupt socket close, silence (no PONG), a fragmented frame,
      a malformed JSON payload, an app change, an app quit.
- [ ] Accepts commands and reflects them in subsequent status messages, so [TEST-05] can
      exercise the full round trip; scriptable to ignore or reject a command instead.
- [ ] `CastClient` integration tests run against it in CI with no hardware.

**Size:** M

---

## TEST-02 — Mapper tests

**Acceptance**
- [ ] Golden tests over real captured payloads from each service.
- [ ] Cases: missing metadata, missing images, empty images array, wrong types, absent
      `playerState`, absent duration.
- [ ] Asserted: the mapper never throws for any input, including `{}` and deeply wrong
      shapes.
- [ ] Property test or fuzz over mutated payloads, if cheap.

**Size:** S

---

## TEST-03 — Enforce layer purity

**As** the developer, **I want** the architecture enforced mechanically, **so that** the
constraints survive contact with a hurry.

**Acceptance**
- [ ] CI fails if `package:flutter` appears anywhere under `lib/cast/` or `lib/domain/`.
- [ ] CI fails if `material.dart` or `cupertino.dart` appears anywhere under `lib/`.
- [ ] CI fails if `lib/ui/` imports `lib/cast/`.
- [ ] CI fails if `LAUNCH` or `LOAD` appears anywhere in `lib/` or `relay/` — the
      never-evict-the-session guarantee, enforced. Other commands are permitted
      ([ADR-0004](../../adr/0004-bidirectional-control.md)) but must appear only in
      `lib/cast/cast_commands.dart`.
- [ ] CI fails if `dart:io` is reachable from the web entrypoint — the check that keeps
      [ADR-0005](../../adr/0005-web-delivery-via-relay.md) true.
- [ ] Implemented as a script, runnable locally, not only in CI.

**Size:** S

---

## TEST-04 — CI

**Acceptance**
- [ ] `flutter analyze` clean, treated as failing.
- [ ] `flutter test` including the fake-device integration tests.
- [ ] `TEST-03` purity checks.
- [ ] Debug builds for Android, iOS **and web** produced on every push. The web build is
      the real guard against `dart:io` creeping back in — it fails loudly at compile time.
- [ ] Runs in under five minutes.

**Size:** S

---

## TEST-05 — Command and optimistic-reconcile tests

**As** the developer, **I want** the control path tested without hardware, **so that** a
regression in revert logic doesn't reach someone's phone.

**Acceptance**
- [ ] Round trip against [TEST-01]: command sent, status reflects it, optimistic state
      reconciles cleanly with no visible flicker.
- [ ] A command the fake ignores reverts after the timeout.
- [ ] A command the fake rejects reverts immediately.
- [ ] Capability gating: a transport command is not sent when the bitmask forbids it.
- [ ] A rate-limited volume drag sends fewer messages than it received drag events, and
      always sends the final value.
- [ ] Inbound volume updates during an active drag do not move the slider.
- [ ] No command is ever emitted with a missing `mediaSessionId`.

**Size:** M
