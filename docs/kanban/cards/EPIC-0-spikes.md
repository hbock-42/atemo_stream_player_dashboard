# EPIC-0 — De-risking spikes

**Goal:** answer the three unknowns that could change the architecture, before building on
top of it. Timebox the whole epic to one day. Spikes produce a written answer in
[`docs/open-questions.md`](../../open-questions.md) and throwaway code, not production code.

---

## SPIKE-01 — Does Spotify Connect surface over the Cast media namespace?

**As** the developer, **I want** to know whether a Spotify Connect session is visible over
CASTV2 on this device, **so that** I know whether EPIC-8 is required work or dead weight.

Resolves [OQ-1](../../open-questions.md#oq-1--does-spotify-connect-surface-through-the-cast-media-namespace).

**Approach:** extend the existing Python `pychromecast` PoC to dump every frame with
namespace and payload. Play from Spotify Connect, then Tidal Connect, then a native Cast
app. Record what each produces.

**Acceptance**
- [ ] For each of Spotify Connect / Tidal Connect / native Cast, recorded: does
      `RECEIVER_STATUS` show an application, what `displayName` and `appId`, and does
      `MEDIA_STATUS` arrive with real metadata?
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

**Approach:** with a phone driving playback, connect a second sender from the Python PoC and
issue each command in turn. Repeat for a native Cast app, Spotify Connect and Tidal Connect
if [SPIKE-01] found them visible at all.

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
