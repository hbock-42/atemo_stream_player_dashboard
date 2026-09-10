# ADR-0004 — The app controls playback, not only observes it

**Status:** Accepted · **Date:** 2026-09-10 · **Supersedes the "observer only" scope of** [ADR-0001](0001-hand-rolled-castv2.md)

## Context

The original scope was read-only: show what's playing. The requirement has grown — the page
should also pause/play, skip, and set volume. This changes the app's relationship to the
device and raises the stakes on [OQ-1](../open-questions.md).

## Decision

Support control. Implement exactly five command families and no more:

| Command | Namespace | Destination | Availability |
|---|---|---|---|
| `SET_VOLUME {level}` / `{muted}` | receiver | `receiver-0` | **Always** — device-level, independent of the casting app |
| `PAUSE` / `PLAY` | media | `transportId` | Requires `mediaSessionId`; gated by bitmask |
| `QUEUE_NEXT` / `QUEUE_PREV` | media | `transportId` | Gated by bitmask; often unsupported |
| `SEEK {currentTime}` | media | `transportId` | Gated by bitmask |
| `STOP` | media | `transportId` | Deliberately **not** exposed in the UI — too easy to mis-tap, and recovery requires the original phone |

`LAUNCH` and `LOAD` remain forbidden. They would evict the live session the office is
listening to. The CI guard in [TEST-03] narrows from "no commands" to "no `LAUNCH`/`LOAD`"
rather than being deleted.

## Capability gating

`MEDIA_STATUS` carries `supportedMediaCommands`, an integer bitmask. The UI is driven from
it: unsupported controls render disabled rather than firing commands that silently do
nothing. Commonly `1=PAUSE, 2=SEEK, 4=STREAM_VOLUME, 8=STREAM_MUTE, 64=QUEUE_NEXT,
128=QUEUE_PREV` — [SPIKE-04] verifies the values this device actually reports before we
rely on them.

Note the distinction: bit 4 is *stream* volume over the media namespace. Device volume over
the receiver namespace is a separate mechanism and is always available. Prefer the latter.

## Why this does not change ADR-0001

This is the strongest case for adopting a package, since `dart_chromecast` and `cast` both
ship control methods. It still fails:

- Their control methods operate on a session **they** launched, tracking a `mediaSessionId`
  and `transportId` from their own `LAUNCH`. Adopting a foreign session is a different path,
  and the one they lack.
- Neither surfaces `supportedMediaCommands`, which is the mechanism control actually needs.
- Both import `dart:io` unconditionally, which breaks the web build ([ADR-0005](0005-web-delivery-via-relay.md)).
  Our own `cast/` can sit behind a conditional import; a dependency's transitive `dart:io`
  cannot.

Device volume via `receiver-0` is a dozen lines. The marginal cost of control is small.

## Consequences

- `NowPlayingSource` gains a nullable `PlaybackControl? get control` — a source may be
  read-only (an unauthorised Spotify source, a relay connection without write access).
- `Playing` gains `capabilities`, `volumeLevel` and `isMuted`.
- The relay's WebSocket becomes bidirectional ([RELAY-05]).
- Optimistic UI is required: a command's effect arrives as an unsolicited `MEDIA_STATUS`
  some hundreds of ms later. Reflect intent immediately, reconcile on the real status,
  and revert if no status confirms within ~2s.
- Anyone on the LAN can now pause the office music. See [OQ-6](../open-questions.md#oq-6--who-is-allowed-to-control-the-speaker).
- If OQ-1 resolves badly, we lose metadata *and* transport control for Spotify Connect —
  but device volume still works, so the degraded mode is a volume-only remote.
