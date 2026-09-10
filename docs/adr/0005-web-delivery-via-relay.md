# ADR-0005 — The relay serves a web UI; GitHub Pages cannot host this

**Status:** Accepted · **Date:** 2026-09-10 · **Promotes the relay from** [ADR-0002](0002-direct-then-relay.md) **to mandatory**

## Context

Proposal considered: deploy the app to GitHub Pages so that one page holds the Cast
connection and everyone connects to that page, instead of every phone connecting to the
device.

## Decision

**Rejected as specified — it cannot work.** Accepted in spirit: one process holds the single
Cast connection and everyone views it over HTTP/WebSocket. That process is the relay,
running on a machine on the office LAN, and it serves the web UI itself.

## Why GitHub Pages cannot work

Two independent blockers, either of which is fatal:

1. **Browsers cannot open raw TCP/TLS sockets.** The only network APIs available to page
   JavaScript are HTTP(S), WebSocket and WebRTC. CASTV2 requires a raw TLS socket to port
   8009 with a self-signed certificate. On Flutter Web `dart:io` does not exist, so
   `SecureSocket` is not merely unavailable — it does not compile.
2. **GitHub Pages executes no code.** It is static file hosting. "The page connects to the
   device" presupposes server-side execution that Pages does not provide; the page runs in
   *each visitor's browser*. So even given sockets, this would be N connections to the
   device — precisely the topology the proposal set out to avoid.

Compounding, were those solved: mDNS is unavailable from a browser, and an HTTPS origin on
`github.io` opening `ws://192.168.x.x` is blocked both as mixed content and by browsers'
tightening local-network access rules.

## What we build instead

```
Streamplayer ──TLS:8009── [ relay, one LAN machine ]
   ONE connection               ├── HTTP  : Flutter Web bundle
                                └── WS    : NowPlaying state + commands
                                      ▼
                     http://streamplayer.local:8080
              a dozen phones, any browser, nothing installed
```

## Rationale

- **One connection to the device**, however many people watch. [OQ-2](../open-questions.md#oq-2--how-many-concurrent-castv2-senders-does-the-device-tolerate)
  ceases to constrain us.
- **No install, no App Store, no TestFlight, no device-count limits.** This removes the
  genuinely painful half of [POL-02]. People open a bookmark.
- **Zero configuration.** The page derives its socket URL from its own origin
  (`ws://${location.host}/ws`). Being served *by* the relay, it knows where the relay is by
  construction. No mDNS, no manual IP, on the web target.
- **Same codebase.** `RelaySource` is pure WebSocket and works on web unchanged, because the
  UI depends only on `NowPlayingSource`.
- Plain HTTP on a LAN is acceptable; nothing here requires a secure context.

## Consequences

- The relay (EPIC-7) moves into M1 and becomes the primary deployment surface.
- `DirectCastSource` must sit behind a conditional import so the web build compiles without
  `dart:io`. Enforced by a CI web build ([EPIC-10]).
- Native Android/iOS builds remain — same code, better for a wall display and for anyone
  wanting an icon — but are no longer the only way in.
- The relay is now a single point of failure for the whole office. [RELAY-04] must cover
  restart-on-boot and a runbook.
- Access from outside the office, if ever wanted, is a Tailscale or Cloudflare tunnel in
  front of the relay — no application change.
- CanvasKit's payload is a few MB on first load. Irrelevant on a LAN; noted so nobody is
  surprised.

## Rejected alternative

Hosting only the *static bundle* on GitHub Pages while the WebSocket points at the LAN
relay. Fails on mixed content (HTTPS page → `ws://` private IP) and local-network access
restrictions, and gains nothing over serving the bundle from the relay.
