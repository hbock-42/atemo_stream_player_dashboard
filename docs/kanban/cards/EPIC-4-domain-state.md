# EPIC-4 — Domain and state

**Goal:** the seam. Everything above this epic is Cast-agnostic; everything below is
replaceable.

---

## DOM-01 — `NowPlaying` sealed model

**Acceptance**
- [ ] `sealed class NowPlaying` with `Connecting`, `Playing`, `Idle`, `Unreachable`.
- [ ] `Playing` carries title, artist, album, artworkUrl, castingApp, isPaused, position,
      duration — all nullable except `isPaused`, because the device may omit any of them.
- [ ] `Playing` also carries `volumeLevel`, `isMuted` and a `Capabilities` value decoded
      from `supportedMediaCommands`.
- [ ] `Idle` carries `volumeLevel` too — device volume works with no app running, so the
      idle screen still has a working control.
- [ ] `Idle` and `Unreachable` are separate types, never one nullable `Playing`.
- [ ] `Unreachable` carries a human-readable reason and a `since` timestamp.
- [ ] Value equality, so the UI doesn't rebuild on identical updates.
- [ ] `toJson`/`fromJson` — this is the relay's wire format ([RELAY-02]).
- [ ] No Flutter import.

**Size:** S

---

## DOM-02 — `NowPlayingSource` interface and `FakeSource`

**As** the developer, **I want** one interface all sources implement, **so that** the UI
can be built and demoed before the protocol works.

**Acceptance**
- [ ] `NowPlayingSource` per [architecture.md](../../architecture.md#the-seam), including
      `PlaybackControl? get control`.
- [ ] `PlaybackControl` with play, pause, next, previous, seek, setVolume, setMuted.
- [ ] `control` is **nullable**, not a no-op implementation, so "this source cannot control
      anything" is a state the UI must handle rather than one it can forget.
- [ ] The stream is broadcast and replays the latest value to new listeners.
- [ ] `FakeSource` cycles scripted states, including a long title, a missing artist, no
      artwork, a partially-capable session, and a drop to `Unreachable`.
- [ ] `FakeSource` can be constructed with `control: null` so [UI-09] is developable.
- [ ] The whole UI can be developed against `FakeSource` with no device present.

**Size:** S

---

## DOM-03 — `MEDIA_STATUS` → `NowPlaying` mapper

**As** a user, **I want** a partly-filled card rather than a crash when the device sends
something odd, **so that** the display never goes blank mid-song.

**Acceptance**
- [ ] Maps title, artist (falling back to `albumArtist`), `albumName`, `images[0].url`,
      `playerState`, `currentTime`, `media.duration`.
- [ ] Every field read defensively — missing keys, nulls, wrong types, empty arrays all
      yield null rather than an exception.
- [ ] A malformed payload never throws out of the mapper; it is logged and produces the
      best partial result.
- [ ] `playerState` maps: `PLAYING`→playing, `PAUSED`→paused, `BUFFERING`→playing,
      `IDLE`→`Idle`.
- [ ] Casting-app name comes from receiver status and is threaded in.
- [ ] Pure function, no I/O, fully unit-tested ([TEST-02]).

**Size:** M

---

## DOM-04 — `DirectCastSource`

**Acceptance**
- [ ] Composes discovery ([EPIC-2]) + `CastClient` ([EPIC-3]) + mapper ([DOM-03]) behind
      `NowPlayingSource`.
- [ ] Emits `Connecting` on start, then the real state.
- [ ] Owns the lifecycle: `dispose()` closes the socket, cancels timers, stops discovery,
      and leaves nothing running.
- [ ] Repeated start/dispose cycles leak nothing.

**Size:** M

---

## STATE-01 — `NowPlayingController` and lifecycle

**As** a user, **I want** the app to reconnect when I bring it back from my pocket,
**so that** I don't stare at a stale or dead screen.

**Acceptance**
- [ ] A `ChangeNotifier`/`ValueNotifier` exposing one `NowPlaying`; no state-management
      package.
- [ ] Selects the source from `AppConfig` ([CORE-04]).
- [ ] `WidgetsBindingObserver`: on `paused` the source is disposed; on `resumed` it is
      restarted. iOS will kill a background socket anyway — this makes it deliberate.
- [ ] A manual retry method for [UI-03].
- [ ] Verified: backgrounding for five minutes and returning shows the correct current
      track within a couple of seconds.

**Size:** M

---

## STATE-02 — Optimistic control with reconcile and revert

**As** a user, **I want** the pause button to respond instantly, **so that** it doesn't feel
broken while the device thinks about it.

Rationale: [architecture.md](../../architecture.md#optimistic-control).

**Acceptance**
- [ ] A command applies its intended state to the exposed `NowPlaying` immediately.
- [ ] The next real `MEDIA_STATUS`/`RECEIVER_STATUS` reconciles the optimistic state.
- [ ] If no confirming status arrives within the timeout measured in [SPIKE-04] (~2s
      default), the optimistic change reverts and the UI shows the true state.
- [ ] An explicitly rejected command reverts immediately rather than waiting for the timeout.
- [ ] A volume drag does not fight the incoming status stream — inbound volume updates are
      ignored while the user is actively dragging, and reconciled on release.
- [ ] Rapid repeated taps do not queue up a backlog of contradictory commands.
- [ ] Fully unit-tested against a scripted source ([TEST-05]) with no device present.

**Size:** M
