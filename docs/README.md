# Atonemo Streamplayer Viewer — Docs

A Flutter app that shows — and controls — what's playing on the office Atonemo
Streamplayer, reachable by anyone on the local network from a browser.

## Start here

| Doc | What's in it |
|---|---|
| [architecture.md](architecture.md) | Layers, module boundaries, the source seam, topology |
| [protocol.md](protocol.md) | CASTV2 wire format, handshake, commands, failure modes |
| [open-questions.md](open-questions.md) | Known unknowns and how the design absorbs them |
| [kanban/board.md](kanban/board.md) | The board: epics, user stories, milestones |
| [adr/](adr/) | Architecture decision records |

## Shape of the thing

```
Streamplayer ──TLS:8009── [ relay, one LAN machine ]
   ONE connection               ├── HTTP  : Flutter Web bundle
                                └── WS    : state + commands
                                      ▼
                     http://streamplayer.local:8080
              a dozen phones, any browser, nothing installed
```

Native Android/iOS builds ship from the same codebase for the wall display and for anyone
who wants an icon. They can connect directly to the device or through the relay.

## Constraints (non-negotiable)

- **Flutter, no `material.dart`, no `cupertino.dart`.** Root is `WidgetsApp`. All visual
  primitives are hand-built. [ADR-0003](adr/0003-no-material-cupertino.md).
- **Minimal dependencies.** Actual set: `multicast_dns`, `web_socket_channel` and
  `shared_preferences` — the last one because config and the last-known device address must
  survive a restart, and it is the only store that works on web (localStorage) as well as
  native, saving us a conditional-import storage layer of our own. The
  CASTV2 protobuf is hand-written, so there is no protobuf runtime and no `protoc` in the
  build; the relay's HTTP and WebSocket server is `dart:io` alone. Anything else needs a
  written reason.
- **Never `LAUNCH`, never `LOAD`.** The app adopts the session already running; launching
  an app would evict whatever the office is listening to. Enforced in CI ([TEST-03]).
  Other commands — pause, skip, volume — are supported. [ADR-0004](adr/0004-bidirectional-control.md).
- **Controls are capability-gated** from `supportedMediaCommands`, never fired blind.
- **The data source is swappable.** UI depends on `NowPlayingSource`, never on Cast.
- **The LAN is the credential.** Everyone on the office Wi-Fi may view and control; nobody
  outside may do either. No PIN, no accounts — the speaker itself has no auth, so this
  matches the existing boundary. Enforced by three layers in [RELAY-05], including an
  `Origin`/`Host` check against DNS rebinding.
  [ADR-0006](adr/0006-lan-membership-is-the-auth-boundary.md).
- **Never expose the relay to the internet.** No port forward, no UPnP, no tunnel. Control
  fails closed if one is ever added.

## Given facts (do not re-research)

- Atonemo publishes no developer API, SDK, docs, or Home Assistant integration.
- The device supports AirPlay 2, Google Cast, Spotify Connect, Tidal Connect.
- mDNS: advertises `_googlecast._tcp`, instance name `Streamplayer-<32 hex chars>`.
- AirPlay 2 is a dead end — receivers do not expose now-playing metadata to third parties.
- Google Cast is the way in. A working Python `pychromecast` proof of concept exists.
- **Browsers cannot open raw TCP/TLS sockets**, so no browser page can speak CASTV2
  directly, and static hosting (GitHub Pages) cannot hold the connection.
  [ADR-0005](adr/0005-web-delivery-via-relay.md).
