# ADR-0002 — Direct connections first, relay as the target topology

**Status:** Accepted · **Date:** 2026-09-10
**Amended 2026-09-10 by [ADR-0005](0005-web-delivery-via-relay.md):** the relay is no longer
a v2 option. Serving a browser-based UI requires it, because browsers cannot open the raw
TLS socket CASTV2 needs. The relay moves into M1 and becomes the primary deployment surface.
The staging below still holds as *build order* — direct first, because it is the relay's own
engine — but not as a question of whether the relay gets built.

## Context

An office of roughly a dozen people wants to see now-playing. Either every phone holds its
own CASTV2 connection to the Streamplayer, or one machine holds a single connection and
fans out to the phones.

## Decision

Ship **direct** in v1. Build **relay** in v2 behind the same `NowPlayingSource` interface.
Both are supported; the app chooses by configuration.

## Rationale

A dozen simultaneous CASTV2 senders against a €99 SoC is a genuine risk. Cast receivers
commonly cap concurrent senders in the low single digits, the cap is undocumented, and
there is no vendor to ask. The failure mode is not merely "the twelfth phone shows an
error" — an overloaded receiver can drop the session that is actually playing music, which
is a bug the whole office hears.

Against that: the relay is infrastructure — a machine that must stay on, be deployed, be
monitored — and v1's value is proving the protocol works and getting something on screens
this week.

The tension resolves because **the relay is the direct client, hosted**. Writing
`DirectCastSource` is not throwaway work; it is the relay's engine. So we do the cheap
thing first without paying for it later.

The relay also, incidentally, fixes three other problems: iOS backgrounding (a sleeping
phone drops its socket and must re-handshake; the relay never sleeps), mDNS discovery
becoming a once-per-network concern instead of once-per-phone, and giving the Spotify Web
API credentials (OQ-1) exactly one place to live rather than being embedded in every phone.

## Consequences

- `cast/` and `domain/` carry no Flutter imports so they run headless. Enforced by Epic 6.
- The relay's wire format is `NowPlaying` serialised to JSON over a WebSocket — the domain
  model, not the Cast payload. The relay owns protocol translation; clients stay dumb.
- [SPIKE-02] measures the real concurrent-sender limit. With the relay now mandatory this
  no longer decides the topology; it tells us how many *native* app users can safely run in
  direct mode alongside the relay's own connection.
- With control ([ADR-0004](0004-bidirectional-control.md)) the relay's WebSocket is
  bidirectional, and the relay becomes the natural place to enforce who may send commands.
