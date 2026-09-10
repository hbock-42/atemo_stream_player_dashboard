# Kanban — Atonemo Streamplayer Viewer

Cards live in [`cards/`](cards/), one file per epic, and are mirrored as GitHub issues on
the project board: **https://github.com/users/hbock-42/projects/2**

The project board is the day-to-day view; these files hold the reasoning. One issue per
card, labelled by epic and size, with an Epic field so the board can be grouped by epic.
Close a card from a commit with `Closes #<n>`.

**Status:** M1 core built. 103 tests pass, `flutter analyze` is clean, the web build
compiles, and `tool/check_layers.sh` passes. Nothing has been run against the real device
yet — every spike in EPIC-0 needs the hardware and the office network.

**Revised 2026-09-10** for two scope changes: playback control
([ADR-0004](../adr/0004-bidirectional-control.md)) and browser delivery via a mandatory
relay ([ADR-0005](../adr/0005-web-delivery-via-relay.md)).

---

## Backlog → Ready → In Progress → Review → Done

| Backlog | Ready | In Progress | Review | Done |
|---|---|---|---|---|
| SPIKE-01…05, WEB-03, WEB-04, EPIC-8, EPIC-9 | CORE-04b, DISC-04, UI-06b | — | everything marked ✅ | — |

Nothing moves to Done until it has been seen working against the real Streamplayer.
"Review" here means built, tested against the fake device, and awaiting hardware.

Legend: ✅ built and tested · ◐ partially built · ○ not started

---

## Epics

| ID | Epic | Goal | Milestone |
|---|---|---|---|
| [EPIC-0](cards/EPIC-0-spikes.md) | De-risking spikes | Answer the unknowns that could change the design | M0 |
| [EPIC-1](cards/EPIC-1-foundation.md) | Project foundation | Flutter project, no-Material shell, theme + primitives | M1 |
| [EPIC-2](cards/EPIC-2-discovery.md) | Device discovery | Find `Streamplayer-*` on the LAN | M1 |
| [EPIC-3](cards/EPIC-3-cast-client.md) | CASTV2 client | TLS, framing, handshake, heartbeat, reconnect, commands | M1 |
| [EPIC-4](cards/EPIC-4-domain-state.md) | Domain & state | `NowPlaying`, `PlaybackControl`, the seam, the controller | M1 |
| [EPIC-5](cards/EPIC-5-ui.md) | UI | Four states, capability-gated controls | M1 |
| [EPIC-6](cards/EPIC-6-testing.md) | Testing & tooling | Fake device, layer purity, CI incl. web build | M1 |
| [EPIC-7](cards/EPIC-7-relay.md) | Relay | One connection, N clients, serves the web UI | **M1 — now mandatory** |
| [EPIC-10](cards/EPIC-10-web.md) | Web target | Flutter Web build, zero-config, browser gotchas | **M1 — the primary way in** |
| [EPIC-8](cards/EPIC-8-spotify.md) | Spotify Web API source | Fallback if OQ-1 / OQ-5 say Cast can't do it | M2 (conditional) |
| [EPIC-9](cards/EPIC-9-polish.md) | Polish & release | Distribution, wall display, diagnostics | M3 |

## Milestones

- **M0 — Spikes.** EPIC-0 only, timeboxed to ~2 days. Outcome: OQ-1 … OQ-5 and OQ-8
  answered. May reorder everything after it. **[SPIKE-05] runs first** — if the office APs
  isolate clients, the architecture needs revisiting before anything is built.
- **M1 — Office-ready.** Someone opens `http://streamplayer.local:8080` on their phone,
  sees the live track, and adjusts the volume. EPIC-1 … EPIC-7, EPIC-10.
- **M2 — Gap-filling.** EPIC-8 if the spikes require it. Control authorisation is settled
  — [ADR-0006](../adr/0006-lan-membership-is-the-auth-boundary.md), no PIN — and ships as
  part of [RELAY-05] in M1.
- **M3 — Shipped.** Wall display up, native builds distributed, diagnostics in place.

The critical path to a usable thing is **EPIC-1 → EPIC-3 → EPIC-4 → EPIC-7 → EPIC-10**.
EPIC-5 can run in parallel against `FakeSource` from day one.

## Card index

| | ID | Title | Epic | Size | Depends on |
|---|---|---|---|---|---|
| ○ | SPIKE-01 | Does Spotify Connect surface over the Cast media namespace? | 0 | M | — |
| ○ | SPIKE-02 | Find the device's concurrent-sender limit | 0 | S | — |
| ○ | SPIKE-03 | Confirm mDNS behaviour when the device is idle | 0 | S | — |
| ○ | SPIKE-04 | Will the device accept commands from a foreign sender? | 0 | M | — |
| ○ | SPIKE-05 | Characterise the office network — **do first** | 0 | S | — |
| ✅ | CORE-01 | Flutter project scaffold, minimal deps | 1 | S | — |
| ✅ | CORE-02 | `WidgetsApp` shell with no Material or Cupertino | 1 | S | CORE-01 |
| ✅ | CORE-03 | Theme tokens and UI primitives incl. slider and disabled states | 1 | M | CORE-02 |
| ◐ | CORE-04 | App configuration and platform-conditional source factory | 1 | S | CORE-01 |
| ✅ | DISC-01 | mDNS browse for `_googlecast._tcp` | 2 | M | CORE-01 |
| ✅ | DISC-02 | Android multicast lock + permissions | 2 | M | DISC-01 |
| ✅ | DISC-03 | iOS Info.plist local network entitlements | 2 | S | DISC-01 |
| ◐ | DISC-04 | Cache last-known address, manual IP fallback | 2 | S | DISC-01 |
| ✅ | CAST-01 | `CastMessage` codec, hand-written | 3 | S | CORE-01 |
| ✅ | CAST-02 | `CastChannel` — TLS + length-prefix framing | 3 | M | CAST-01 |
| ✅ | CAST-03 | Handshake to receiver and media namespaces | 3 | M | CAST-02 |
| ✅ | CAST-04 | Heartbeat PING/PONG and liveness timeout | 3 | S | CAST-03 |
| ✅ | CAST-05 | Handle app change, app quit, Backdrop | 3 | M | CAST-03 |
| ✅ | CAST-06 | Reconnect with exponential backoff and rediscovery | 3 | M | CAST-04 |
| ✅ | CAST-07 | `CastCommands` — volume, transport, capability gating | 3 | M | CAST-03, SPIKE-04 |
| ✅ | DOM-01 | `NowPlaying` sealed model incl. volume and capabilities | 4 | S | CORE-01 |
| ✅ | DOM-02 | `NowPlayingSource` + `PlaybackControl` + `FakeSource` | 4 | S | DOM-01 |
| ✅ | DOM-03 | `MEDIA_STATUS`/`RECEIVER_STATUS` → `NowPlaying` mapper | 4 | M | DOM-01 |
| ✅ | DOM-04 | `DirectCastSource` wiring discovery + client + mapper | 4 | M | CAST-06, DOM-03 |
| ✅ | STATE-01 | `NowPlayingController` and app lifecycle handling | 4 | M | DOM-04 |
| ✅ | STATE-02 | Optimistic control with reconcile and revert | 4 | M | STATE-01, CAST-07 |
| ✅ | UI-01 | Now-playing screen | 5 | M | CORE-03, STATE-01 |
| ✅ | UI-02 | Idle state | 5 | S | UI-01 |
| ✅ | UI-03 | Unreachable state with retry affordance | 5 | S | UI-01 |
| ✅ | UI-04 | Artwork loading, fallback, cleartext-URL handling | 5 | M | UI-01 |
| ✅ | UI-05 | Casting-app attribution | 5 | S | UI-01 |
| ✅ | UI-06 | Transitions between states | 5 | S | UI-01…03 |
| ✅ | UI-07 | Transport controls, capability-gated | 5 | M | UI-01, STATE-02 |
| ✅ | UI-08 | Volume slider and mute | 5 | M | UI-01, STATE-02 |
| ✅ | UI-09 | Read-only mode when the source offers no control | 5 | S | UI-07 |
| ✅ | TEST-01 | Fake CASTV2 device for tests | 6 | M | CAST-02 |
| ✅ | TEST-02 | Mapper tests incl. malformed payloads | 6 | S | DOM-03 |
| ✅ | TEST-03 | Enforce layer purity and the no-LAUNCH rule | 6 | S | CORE-02 |
| ◐ | TEST-04 | CI: analyze, test, build android + ios + **web** | 6 | S | TEST-03 |
| ✅ | TEST-05 | Command and optimistic-reconcile tests | 6 | M | STATE-02, TEST-01 |
| ✅ | RELAY-01 | Headless relay server reusing `cast/` | 7 | M | CAST-06 |
| ✅ | RELAY-02 | WebSocket fan-out of `NowPlaying` JSON | 7 | M | RELAY-01 |
| ✅ | RELAY-03 | `RelaySource` client | 7 | S | RELAY-02, DOM-02 |
| ◐ | RELAY-04 | Relay deployment, stable hostname, runbook | 7 | M | RELAY-02 |
| ✅ | RELAY-05 | Inbound command channel, LAN-only authorisation | 7 | M | RELAY-02, CAST-07 |
| ✅ | RELAY-06 | Serve the Flutter Web bundle from the relay | 7 | S | RELAY-02, WEB-01 |
| ✅ | WEB-01 | Flutter Web build with `dart:io` excluded | 10 | M | CORE-04, RELAY-03 |
| ✅ | WEB-02 | Zero-config relay URL from page origin | 10 | S | WEB-01 |
| ○ | WEB-03 | Browser gotchas: autoplay-free, wake lock, mobile Safari | 10 | M | WEB-01 |
| ○ | WEB-04 | Add-to-home-screen manifest | 10 | S | WEB-01 |
| ○ | SPOT-01 | Spotify OAuth for the speaker's account | 8 | M | SPIKE-01 |
| ○ | SPOT-02 | `SpotifyWebApiSource` incl. control endpoints | 8 | M | SPOT-01, DOM-02 |
| ○ | SPOT-03 | Compose Cast + Spotify sources | 8 | M | SPOT-02 |
| ○ | POL-01 | Keep-awake / kiosk mode for a wall display | 9 | S | UI-01 |
| ○ | POL-02 | Native builds for people who want an icon | 9 | S | TEST-04 |
| ○ | POL-03 | Diagnostics screen | 9 | S | STATE-01 |

Sizes: S ≈ half a day, M ≈ 1–2 days, L ≈ 3+.

## What is not done, and why

| Gap | Why |
|---|---|
| Every spike (EPIC-0) | Needs the physical device and the office network. These are yours to run; SPIKE-05 first. |
| CORE-04, DISC-04 — persistence | Config and the last-known address are held in memory. Persisting them is a small change gated on SPIKE-03's answer about whether the device keeps advertising while idle. |
| TEST-04 — CI | `tool/check_layers.sh` runs locally and the commands are known; no CI file is committed because the host is not chosen. |
| RELAY-04 — deployment | The runbook is written (`relay/README.md`); install-as-a-service and the hostname decision need OQ-7 answered on the real network. |
| WEB-03, WEB-04 | Browser lifecycle and add-to-home-screen. Worth doing once the relay is actually deployed and someone has opened it on a phone. |
| Native builds | Android needs the SDK, which is not installed on this machine; iOS was not built. The web path is the primary one regardless (ADR-0005). |
