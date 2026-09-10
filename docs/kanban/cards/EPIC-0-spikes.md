# EPIC-0 — De-risking spikes

**Goal:** answer the three unknowns that could change the architecture, before building on
top of it. Timebox the whole epic to one day. Spikes produce a written answer in
[`docs/open-questions.md`](../../open-questions.md) and throwaway code, not production code.

---

## SPIKE-01 — Which services surface over the Cast media namespace?

**As** the developer, **I want** to know which of the services this office actually uses are
visible over CASTV2 on this device, **so that** I know whether EPIC-8 is required work, dead
weight, or the wrong shape.

The office casts from **Spotify, Tidal, Deezer and SoundCloud**. Deezer and SoundCloud use
Google Cast proper and should publish full metadata; Spotify Connect and Tidal Connect are
separate protocols and may publish nothing. Test all of them — the difference is invisible
from outside.

Resolves [OQ-1](../../open-questions.md#oq-1--does-spotify-connect-surface-through-the-cast-media-namespace).

**Approach:** `cd relay && dart run bin/spike.dart probe --host <ip> --seconds 180`, which
dumps every frame with namespace and payload using the same client the relay ships. Play
from each service in turn. See [docs/spikes.md](../../spikes.md).

**Acceptance**
- [ ] For **each service the office uses** — Spotify, Tidal, Deezer, SoundCloud, and any
      other — recorded: does `RECEIVER_STATUS` show an application, what `displayName` and
      `appId`, and does `MEDIA_STATUS` arrive with real metadata?
- [ ] Recorded whether the mDNS TXT `rs=` status line tracks the track for every service.
      If it does, it is a service-agnostic fallback and changes EPIC-8's shape entirely.
      **Raised in priority:** office Android phones already display what is playing
      without having started it, which is this field being read straight off the LAN.
      Run `dart run bin/spike.dart txt --seconds 600` while switching services; if `rs=`
      follows every one, it is a data source that needs no CASTV2 connection, consumes no
      sender slot (so [OQ-2] stops mattering), and works for services that publish nothing
      on the media namespace.
- [ ] Sample payloads saved to `docs/samples/` — these become the [TEST-01] fixtures.
- [ ] OQ-1 updated with the answer and a verdict on EPIC-8.

**Size:** M

---

## SPIKE-02 — Find the device's concurrent-sender limit

**As** the developer, **I want** to know how many simultaneous CASTV2 connections the
Streamplayer tolerates, **so that** I know whether the direct topology is viable for an
office of a dozen.

Resolves [OQ-2](../../open-questions.md#oq-2--how-many-concurrent-castv2-senders-does-the-device-tolerate).

**Approach:** script N concurrent connections, each doing the full handshake and holding
heartbeats. Walk N from 1 upward. Music must be playing throughout.

**Acceptance**
- [ ] The number at which new connections are refused or misbehave is recorded.
- [ ] Explicitly checked and recorded: does adding senders ever disturb the *playing*
      session? This is the outcome that matters most.
- [ ] Recorded whether existing connections survive when the limit is hit.
- [ ] OQ-2 updated. If the limit is ≤ 4, EPIC-7 is promoted into M1.

**Size:** S

---

## SPIKE-03 — Confirm mDNS behaviour when the device is idle

**As** the developer, **I want** to know whether the device keeps advertising
`_googlecast._tcp` while idle or in standby, **so that** I know whether address caching
([DISC-04]) is required to tell `Idle` from `Unreachable`.

Resolves [OQ-3](../../open-questions.md#oq-3--does-the-devices-mdns-record-survive-standby).

**Acceptance**
- [ ] `dns-sd -B _googlecast._tcp` observed while playing, while idle, and after the device
      has been idle for 30+ minutes.
- [ ] Recorded whether port 8009 still accepts a connection when the mDNS record is absent.
- [ ] OQ-3 updated; [DISC-04] marked required or optional.

**Size:** S

---

## SPIKE-04 — Will the device accept commands from a foreign sender?

**As** the developer, **I want** to know which commands a second sender can issue against a
session it did not launch, **so that** I know whether the control UI is a real remote or a
volume knob.

Resolves [OQ-5](../../open-questions.md#oq-5--will-the-device-accept-commands-from-a-sender-that-did-not-launch-the-session).

**Approach:** `dart run bin/spike.dart commands --host <ip> --i-am-at-the-speaker`, with
playback started from a different device. Repeat for each service [SPIKE-01] found visible —
an app that reports metadata does not necessarily accept commands from a foreign sender.

**Acceptance**
- [ ] For each command — `SET_VOLUME` (receiver), `PAUSE`, `PLAY`, `QUEUE_NEXT`,
      `QUEUE_PREV`, `SEEK` — recorded: accepted, silently ignored, or an error frame.
- [ ] The actual `supportedMediaCommands` value the device reports is recorded, and the
      bitmask table in [protocol.md](../../protocol.md#supportedmediacommands) corrected if
      it differs from the assumed values.
- [ ] Confirmed that `SET_VOLUME` to `receiver-0` works with **no app running** — this is
      the guaranteed floor the design leans on.
- [ ] Recorded what a *rejected* command looks like on the wire. [STATE-02] needs to detect
      this to revert the optimistic UI.
- [ ] Latency measured: command sent → confirming status received. Sets the revert timeout.
- [ ] OQ-5 updated.

**Size:** M

---

## SPIKE-05 — Characterise the office network

**As** the developer, **I want** to know whether the office Wi-Fi permits device-to-device
traffic and whether guests share the subnet, **so that** the relay topology and the
authorisation model both rest on facts.

Made load-bearing by [ADR-0006](../../adr/0006-lan-membership-is-the-auth-boundary.md).
Resolves [OQ-8](../../open-questions.md#oq-8--is-the-office-wi-fi-actually-the-boundary-we-think-it-is).
**Do this first** — a bad answer invalidates the architecture, not just a card.

**Acceptance**
- [ ] **AP client isolation:** from a phone on office Wi-Fi, ping and open a TCP connection
      to another device on the same network. If blocked, discovery, the relay and possibly
      the speaker connection are all dead, and a network change or a wired relay host is a
      prerequisite for everything else. Record the answer before any other work starts.
- [ ] **mDNS across the subnet:** confirm `_googlecast._tcp` is visible from a phone, not
      only from a laptop on Ethernet. Some APs filter multicast.
- [ ] **Guest SSID:** determine whether a guest network exists and whether it can reach the
      main subnet. Report to the user — it decides whether "everyone on the Wi-Fi" matches
      their intent, and that is their call, not ours.
- [ ] **UPnP:** confirm the router will not auto-expose the relay's port. ADR-0006 layer 1
      depends on this.
- [ ] Candidate relay hosts identified, with a note on whether each is wired or wireless
      and whether it stays powered.
- [ ] OQ-8 updated; ADR-0006 amended if any assumption fails.

**Size:** S
