# Known unknowns

## OQ-1 — Which of the services this office uses surface on the Cast media namespace?

**Partly unknown, and the risk is narrower than it first looks.** People here cast from
Spotify, Tidal, Deezer and SoundCloud. Those split into two groups, and only one is in doubt:

| Group | Services | Expectation |
|---|---|---|
| **Google Cast senders** — the app launches a real Cast receiver app, which gets a `transportId` and publishes `MEDIA_STATUS` | Deezer, SoundCloud, YouTube Music, anything casting from Chrome | Should work fully. This is the path the client is built for. |
| **Proprietary "Connect" protocols** — a separate stack that is not Google Cast at all | Spotify Connect, Tidal Connect | May publish nothing on `urn:x-cast:com.google.cast.media`. This is the actual open question. |

So the likely outcome is that Deezer and SoundCloud simply work, and the doubt is confined
to the two Connect protocols. Confirming that is worth more than assuming it: the two groups
are indistinguishable from the outside, and "Spotify" appearing as a Cast app on one
firmware and not another is exactly the kind of thing no vendor documents here.

**How the design absorbs it.** The UI depends on `NowPlayingSource`, not on Cast, and
nothing in `lib/` branches on which service is playing — the only `displayName` comparison
in the whole client is the one that detects the idle Backdrop app. A service that reports
metadata renders; one that does not, does not.

The fallbacks differ in how well they scale:

- **A Web API source per service** (EPIC-8, currently written for Spotify) covers exactly
  one service and needs its own OAuth. Four services would mean four of them.
- **The mDNS `rs=` field** is service-agnostic. The TXT record carries a status line for
  whatever is playing, whoever launched it — see the network observation below. Coarse, but
  it covers every service at once and costs no sender slot.

If several services turn out to be invisible, the second is the better answer.

**How we resolve it.** Card [SPIKE-01] — play from **each service the office actually uses**
and dump every frame the client receives. Do this early; it decides whether EPIC-8 is real
work, and which shape it should take.

**Stakes raised by control.** With [ADR-0004](adr/0004-bidirectional-control.md) a bad
answer costs metadata *and* transport control for the affected service. Note the
asymmetry: device volume goes through `receiver-0` and works regardless of the casting app,
so the worst case degrades to a volume-only remote, not to nothing.

**Fallback if a Connect protocol is silent.** For Spotify specifically, the device is also a
Spotify Connect endpoint, so the Web API reports the correct track and offers
`PUT /v1/me/player/pause`, `/play`, `/next`, `/volume` — control survives behind the same
`PlaybackControl` interface. Deezer and SoundCloud have APIs too, but each needs its own
OAuth and its own mapping, which is why the service-agnostic `rs=` route is worth checking
first.

## OQ-2 — How many concurrent CASTV2 senders does the device tolerate?

**Unknown, and unknowable from vendor docs (there are none).** Cast receivers commonly cap
concurrent senders in the low single digits. Twelve phones each holding a TLS session with
its own heartbeat is a plausible way to make a €99 device misbehave — worst case it drops
the *playing* session.

**Largely defused.** [ADR-0005](adr/0005-web-delivery-via-relay.md) makes the relay
mandatory for the web UI, so the normal case is one connection regardless of audience size.
This question now only bounds how many *native* app users may run in direct mode alongside
the relay's connection.

**How we resolve it.** Card [SPIKE-02] — open N connections from a script, walk N up, record
where it breaks. If the answer is ≥ 8 the direct topology is defensible for this office; if
it is ≤ 4, the relay stops being optional.

## OQ-3 — Does the device's mDNS record survive standby?

Some receivers stop advertising when idle. If so, a cached IP is the only way to
distinguish `Idle` from `Unreachable` after a period of silence. Card [DISC-04] covers
last-known-address caching; the answer determines whether it is required or merely nice.


**Suggestive observation, 2026-09-15 (not yet a controlled result):** while the
device was casting, `dns-sd -B _googlecast._tcp` found it consistently. Minutes
later, after the set had ended and nothing was playing, the same browse found
**zero** advertisements — not the device advertising with `st=0`, but no record
at all. If that holds under a proper play → stop → wait test, it means the
device stops advertising when idle, and discovery alone cannot tell "idle" from
"gone". That makes DISC-04 (cache the last address and probe port 8009 directly)
the way to keep `Idle` and `Unreachable` distinct, which is a stated design
goal. Confirm deliberately before relying on it — a 6s browse can also just miss
a slow responder.

## OQ-4 — Artwork URL reachability

Artwork URLs in `MEDIA_STATUS` may be device-local (`http://<deviceIp>:8008/...`) rather
than public CDN URLs. Device-local means plain HTTP, which trips Android 9+ cleartext
policy. Card [UI-04] handles both, plus the no-artwork case.

## OQ-5 — Will the device accept commands from a sender that did not launch the session?

**Unknown.** Adopting a foreign session and reading from it is one thing; commanding it is
another. Some receiver apps accept media commands from any connected sender, others only
from the session originator. `supportedMediaCommands` advertises what the *app* supports,
not necessarily what *we* are permitted to do.

**How the design absorbs it.** `PlaybackControl` is nullable on `NowPlayingSource` and the
UI already handles a read-only source. Device volume via `receiver-0` is a different
mechanism and is expected to work regardless, so there is a guaranteed floor.

**How we resolve it.** Card [SPIKE-04] — from a second sender, while a phone drives playback,
try each command and record what happens. Also record what a rejected command looks like on
the wire, since we need to detect it to revert the optimistic UI.

## OQ-6 — Who is allowed to control the speaker? — **RESOLVED 2026-09-10**

**Decision: everyone on the office Wi-Fi may view and control; nobody outside it may do
either.** No PIN, no accounts. The network is the credential. Recorded as
[ADR-0006](adr/0006-lan-membership-is-the-auth-boundary.md).

Proportionate because the Streamplayer itself has no authentication — anyone on the LAN can
already control it from any Cast app. We match the existing boundary rather than widening it.

Enforced in three layers by [RELAY-05]: never exposed to the internet; commands rejected
unless the real socket peer is an RFC1918 address (`X-Forwarded-For` never trusted); and
`Origin`/`Host` validated on the WebSocket upgrade to defeat DNS rebinding, which is the one
attack path a LAN-only unauthenticated service still has.

Two properties of the office network now matter to correctness — see [SPIKE-05].

## OQ-7 — Does the relay host have a stable name on the office network?

The web UI's value depends on people being able to type or bookmark something memorable.
`http://streamplayer.local:8080` requires working mDNS resolution from the clients, which
Android has historically been inconsistent about. The fallback is a static IP and a
bookmark. Card [RELAY-04] resolves this by trying both on real handsets.

## OQ-8 — Is the office Wi-Fi actually the boundary we think it is?

[ADR-0006](adr/0006-lan-membership-is-the-auth-boundary.md) makes Wi-Fi membership the
credential, which makes two unknowns about the office network load-bearing.

**Guest SSID.** If a guest network shares a subnet with the main one, or is routed to it,
then "everyone on the office Wi-Fi" quietly includes visitors, contractors, and anyone ever
given the guest password. If guest is VLAN-isolated, there is no issue. Unknown which
applies here.

**AP client isolation.** Some office access points block device-to-device traffic entirely.
If that is enabled, mDNS discovery fails *and* phones cannot reach the relay *and* the relay
may not reach the speaker — the whole approach stops working, not just one card. This is the
highest-impact unknown remaining and the cheapest to check.

**How we resolve it.** Card [SPIKE-05], early. If client isolation is on, we need a wired
host or a network change before anything else is worth building.

## CASTV2 confirmed against the real device, 2026-09-15

The full client — discovery, handshake, media status — ran against the real
Streamplayer and returned live metadata:

```
app=SoundCloud  title=14. Angelillo & Hamel - Je Veux te Dire une Chanson
                artist=Super_Breaks  supportedMediaCommands=274639  volume=0.66
```

**SPIKE-01, partial answer:** SoundCloud casts as a real Google Cast app
(`appId B143C57E`, `appType WEB`), publishes `urn:x-cast:com.google.cast.media`,
and its `MEDIA_STATUS` carries full title and artist. So a Google-Cast sender
surfaces completely. Spotify Connect and Tidal Connect — the proprietary
protocols — remain the open half of the question; test them by playing from
each while running `dart run bin/spike.dart probe --host <ip>`.

**Heartbeat stable over time (CAST-04):** the relay held a single CASTV2
connection to the real device for a full minute — `playing` throughout, zero
disconnects, zero errors. The PING/PONG handling keeps the session alive; the
device only drops a sender that fails to heartbeat (as the raw probe did). So
reconnect (CAST-06) is not exercised by normal operation, only by a real outage.

**SPIKE-04, first data:** the device reports `supportedMediaCommands=274639`
for SoundCloud, so it advertises a rich command set (that value includes pause,
seek, queue-next/prev and more). Whether it *accepts* those commands from a
sender that did not launch the session is still untested — that needs
`dart run bin/spike.dart commands --host <ip> --i-am-at-the-speaker`, which
changes real playback, so it waits until someone is at the speaker.

**The bug this exposed:** the handshake `GET_STATUS` carried no `requestId`.
The real device treats that as malformed and never replies, so the client hung
forever at a stage every test passed — because the fake device answered
regardless. Fixed, with a regression test whose fake device refuses a
requestId-less GET_STATUS the way the hardware does. This is the first thing to
check whenever "works in tests, hangs on hardware" recurs: the fake must be as
strict as the device, or the tests are theatre.

## Observed on the network, 2026-09-10

Gathered with `dns-sd` from a machine on the same LAN as a real Streamplayer.
Not a spike result — no CASTV2 socket was opened — but it confirms several
assumptions the design rests on, and adds one that was not anticipated.

```
Streamplayer-38067793cb7c81ff4c11baa216b5de90._googlecast._tcp.local.
  -> 38067793-cb7c-81ff-4c11-baa216b5de90.local.:8009
  TXT: md=Streamplayer  fn=The Kids 🕺  st=1  rs=Casting: Dor Fodida
       ca=198660  ve=05  ic=/setup/icon.png  id=38067793…
```

Confirmed:

- The instance name really is `Streamplayer-<32 hex>`, which is what
  `kStreamplayerInstance` matches in `mdns_discovery.dart`.
- The advertised port really is 8009.
- `fn` carries the owner's friendly name, which is what discovery reads — and
  it contains an emoji, so anything displaying it must be UTF-8 clean.
- The device advertises *while casting*. Whether it keeps advertising when idle
  is still [OQ-3](#oq-3--does-the-devices-mdns-record-survive-standby).

**Corroborated in the office:** several people report that their Android phones
show what is playing on the speaker without any of them having started it. That
is this TXT record. Android's Cast framework browses `_googlecast._tcp` and
reads `rs=` — the receiver status text — with no connection to the device at
all. Everyone's phone already does what this section describes, which is about
as strong a demonstration as could be asked for that the field is live,
broadcast to the whole LAN, and costs no sender slot.

**Proven end to end, 2026-09-15.** `relay --txt` served the real speaker's
current track — `Matières #1 - Présentée par Guessaï` on `The Kids 🕺` — to a
browser, on the very machine where every Dart socket to the LAN is refused. The
relay reads the record through `dns-sd` when its own sockets find nothing, and
the browser renders it as view-only. This is the first time the whole stack has
run against real hardware, and it did so with zero connections to the device.

**Unanticipated, and relevant to [OQ-1](#oq-1--which-of-the-services-this-office-uses-surface-on-the-cast-media-namespace):**
the TXT record carries `st=1` (an app is running) and `rs=` with a
human-readable status line — here `Casting: Dor Fodida`. That is now-playing
information available over plain mDNS, with no CASTV2 connection and no sender
slot consumed. It is coarse — one string, no artist/album split, no artwork —
but if Spotify Connect turns out to be invisible on the media namespace, this
is a third fallback alongside the Spotify Web API, and a much cheaper one.
Worth checking during SPIKE-01 whether `rs` changes for Spotify and Tidal
sessions.

**Not testable from the development sandbox:** outbound LAN sockets are blocked
there for interpreted processes — Dart and Python both get `No route to host`
where `nc` succeeds. The spikes must be run from a normal shell on the office
network. See [docs/spikes.md](spikes.md).

## OQ-9 — This Mac blocks Dart's LAN access; Apple's own tools get through

**Observed 2026-09-10 on macOS 26.1 (a managed work laptop), in a normal
terminal — not a sandbox.**

Against a Streamplayer that is demonstrably present — it answers `ping`, ARP
resolves it, `nc -z 192.168.1.131 8009` succeeds, `dns-sd` browses it — every
Dart network call to it fails:

```
  ✓ ping (system)              works
  ✓ nc to :8009 (system)       works
  ✗ TCP to :8009 (Dart)        fails      No route to host, errno 65
  ✓ dns-sd browse (system)     works
  ✗ mDNS browse (Dart)         fails      No route to host, errno 65
```

So it is not mDNS specifically, not the multicast route (which exists and points
at en0), not the interface, and not the CASTV2 client. Plain TCP from Dart to a
host this machine can ping is refused at the OS level.

**A wrong turn worth recording:** the first hypothesis was the macOS 15+ Local
Network permission. It is not that — iTerm is enabled in
Privacy & Security → Local Network and it still fails. Compiling with
`dart compile exe` and running the binary directly fails identically, so it is
not `dart run` spawning something unattributed either.

**Most likely now:** endpoint security on a managed laptop allowing Apple-signed
binaries and blocking unknown ones. Unproven.

**How to check on any machine:** `dart run bin/spike.dart doctor --host <ip>`
runs Dart and the system tools against the same device and says which side
fails.

**Consequences:**

- Nothing to fix in this codebase; the failures now report the real OS error
  instead of "could not reach the Streamplayer", which hid it.
- **It matters for deployment.** The relay must run on a machine whose Dart
  processes are allowed to reach the LAN. A Raspberry Pi or any unmanaged box
  avoids the question entirely; a managed work laptop is the worst candidate,
  which is worth knowing before RELAY-04 picks a host.
- The spikes are blocked on this machine specifically, not in general.
