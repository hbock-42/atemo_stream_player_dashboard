# Atonemo Streamplayer Dashboard

[![CI](https://github.com/hbock-42/atemo_stream_player_dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/hbock-42/atemo_stream_player_dashboard/actions/workflows/ci.yml)

A Flutter app that shows — and controls — what's playing on the office Atonemo
Streamplayer over Google Cast (CASTV2), reachable from a browser by anyone on the office
Wi-Fi. Nobody installs anything.

See [docs/README.md](docs/README.md) for the full picture: architecture, protocol, ADRs,
and the constraints this project holds itself to (no Material/Cupertino, minimal
dependencies, never `LAUNCH`/`LOAD`, LAN-as-credential). The day-to-day plan lives on
[docs/kanban/board.md](docs/kanban/board.md).

## The two packages

| Package | Where | What |
|---|---|---|
| App | repo root | The Flutter app: UI, the hand-rolled CASTV2 client, mDNS discovery. Ships to the browser only ([ADR-0007](docs/adr/0007-web-only-client.md)); the client and discovery code is what the relay runs. |
| Relay | [`relay/`](relay/) | A pure-Dart server that holds the one CASTV2 connection to the Streamplayer, serves the built web UI, and fans state out to browsers over a WebSocket. It runs the app's `lib/cast/`, `lib/domain/` and `lib/discovery/` code unchanged — see [`relay/README.md`](relay/README.md). |

A browser can't open the raw TLS socket CASTV2 needs, so the relay does it once on
everyone's behalf ([ADR-0005](docs/adr/0005-web-delivery-via-relay.md)).

## Where to find it

There is **no public URL, by design.** The relay is never exposed to the internet — that is
layer 1 of the access model ([ADR-0006](docs/adr/0006-lan-membership-is-the-auth-boundary.md)),
and control switches itself off if a tunnel is ever put in front of it.

| What | URL | Who can reach it |
|---|---|---|
| The app | `http://<relay-host>:8080` | anyone on the office Wi-Fi |
| Wall display | `http://<relay-host>:8080/?wall` | same, in kiosk layout |
| UI demo, no speaker needed | `http://<relay-host>:8080/?demo` | scripted data, works anywhere |
| Relay health | `http://<relay-host>:8080/health` | for checking it is alive |
| Project board | <https://github.com/users/hbock-42/projects/2> | public |

`<relay-host>` is whichever machine runs the relay — `streamplayer.local` if mDNS resolves
on your network, otherwise its IP. Deciding that is part of
[SPIKE-05](docs/spikes.md).

`?demo` runs the UI on scripted data with no relay and no speaker, so the same bundle can be
shown to people who are not on the office network.

## Run the app

```bash
flutter pub get
flutter run -d chrome
```

## Run the relay

```bash
# From the repo root, build the web UI the relay will serve:
flutter build web

cd relay
flutter pub get
dart run bin/relay.dart --port 8080 --web ../build/web

# Or against an in-memory fake device, with no speaker on the network:
dart run bin/relay.dart --demo --port 8080 --web ../build/web
```

## Look at the UI

The app is web-only, so screenshots come from a real browser at real device sizes:

```bash
dart run tool/screenshot.dart http://127.0.0.1:8080/ build/screenshots
```

It drives Chrome over the DevTools protocol. `chrome --headless --screenshot
--window-size=360,800` does **not** give a 360px viewport — Chrome enforces a minimum
window width, so the capture is the top-left corner of a wider render and every narrow
layout looks broken when it is not.

Then open `http://<relay-host>:8080` from any device on the office Wi-Fi. Full options
and troubleshooting are in [`relay/README.md`](relay/README.md).

## Tests and checks

```bash
flutter analyze                        # app — must be clean
flutter test                           # app — 71 tests

cd relay
flutter pub get
dart analyze                           # relay
dart test                              # relay — 32 tests

./tool/check_layers.sh                 # architecture guard (see below)
flutter build web                      # also the guard against dart:io leaking into web
```

`tool/check_layers.sh` enforces the architecture mechanically: no Material/Cupertino
anywhere, no Flutter imports in `lib/cast/` or `lib/domain/`, the UI never imports
`lib/cast/` directly, no `LAUNCH`/`LOAD` payloads, and `dart:io` never reachable from
`lib/ui/` or `lib/state/`. All of the above runs in CI on every push and pull request —
see [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
