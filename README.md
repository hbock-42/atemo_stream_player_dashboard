# Atonemo Streamplayer Dashboard

[![CI](https://github.com/hbock-42/atemo_stream_player_dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/hbock-42/atemo_stream_player_dashboard/actions/workflows/ci.yml)

A Flutter app that shows — and controls — what's playing on the office Atonemo
Streamplayer over Google Cast (CASTV2), reachable by anyone on the local network from a
browser, plus native Android/iOS builds.

See [docs/README.md](docs/README.md) for the full picture: architecture, protocol, ADRs,
and the constraints this project holds itself to (no Material/Cupertino, minimal
dependencies, never `LAUNCH`/`LOAD`, LAN-as-credential). The day-to-day plan lives on
[docs/kanban/board.md](docs/kanban/board.md).

## The two packages

| Package | Where | What |
|---|---|---|
| App | repo root | The Flutter app: UI, the hand-rolled CASTV2 client, mDNS discovery. Runs on web, Android, and iOS. |
| Relay | [`relay/`](relay/) | A pure-Dart server that holds the one CASTV2 connection to the Streamplayer, serves the built web UI, and fans state out to browsers over a WebSocket. It runs the app's `lib/cast/`, `lib/domain/` and `lib/discovery/` code unchanged — see [`relay/README.md`](relay/README.md). |

A browser can't open the raw TLS socket CASTV2 needs, so the relay does it once on
everyone's behalf ([ADR-0005](docs/adr/0005-web-delivery-via-relay.md)).

## Run the app

```bash
flutter pub get
flutter run            # pick a device, or -d chrome / -d android / -d ios
```

## Run the relay

```bash
# From the repo root, build the web UI the relay will serve:
flutter build web

cd relay
flutter pub get
dart run bin/relay.dart --port 8080 --web ../build/web
```

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
