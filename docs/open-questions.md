# Known unknowns

## OQ-1 — Does Spotify Connect surface through the Cast media namespace?

**Unknown.** Native Cast sessions certainly do. Spotify Connect on some receivers runs as a
separate stack that does *not* publish to `urn:x-cast:com.google.cast.media`; on others it
appears as a Cast app with full metadata. Tidal Connect has the same ambiguity.

**How the design absorbs it.** The UI depends on `NowPlayingSource`, not on Cast. If
Spotify Connect turns out to be invisible over CASTV2, we add `SpotifyWebApiSource`
(OAuth against `/v1/me/player/currently-playing` for the account driving the speaker) and
compose it with the Cast source behind the same interface. Zero UI change.

**How we resolve it.** Card [SPIKE-01] — play from Spotify on the device, dump every frame
the client receives, and record the answer here. Do this early; it changes how much of
Epic 7 is needed, and nothing else.

**Stakes raised by control.** With [ADR-0004](adr/0004-bidirectional-control.md) a bad
answer here costs metadata *and* transport control for Spotify Connect sessions. Note the
asymmetry: device volume goes through `receiver-0` and works regardless of the casting app,
so the worst case degrades to a volume-only remote, not to nothing.

**Fallback if both fail.** The device is also a Spotify Connect *endpoint*, so the Web API
route will report the correct track and device name even when CASTV2 is silent — and the
Web API also offers `PUT /v1/me/player/pause`, `/play`, `/next`, `/volume`, so control
survives the fallback too, behind the same `PlaybackControl` interface.

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
