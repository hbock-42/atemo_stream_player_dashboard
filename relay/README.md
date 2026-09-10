# Streamplayer relay

Holds the single CASTV2 connection to the office Streamplayer and serves the web
UI plus a WebSocket to everyone else.

A browser cannot open the raw TLS socket CASTV2 requires, so this process does
it once on everyone's behalf. The device therefore only ever sees one sender,
however many people are watching. See
[ADR-0005](../docs/adr/0005-web-delivery-via-relay.md).

It runs the app's protocol code unchanged — `lib/cast/`, `lib/domain/` and
`lib/discovery/` carry no Flutter imports precisely so that this is possible,
enforced by `tool/check_layers.sh`.

## Run it

```bash
# From the repo root, build the web UI the relay will serve:
flutter build web

cd relay
flutter pub get
dart run bin/relay.dart --port 8080 --web ../build/web
```

Options:

| Flag | Meaning |
|---|---|
| `--port` | HTTP/WebSocket port (default 8080) |
| `--web` | directory of `flutter build web` output; omit to serve the socket only |
| `--host` | skip discovery and use this device IP, for networks that block multicast |

Then open `http://<relay-host>:8080` from any phone on the office Wi-Fi.

## Endpoints

| Path | Purpose |
|---|---|
| `/` | the Flutter web UI |
| `/ws` | state broadcast and inbound commands |
| `/health` | connection state, client count, uptime — for checking it is alive |

## Access

Everyone on the office Wi-Fi may view and control; nobody outside may do either.
No PIN, no accounts — the Streamplayer itself has no authentication, so this
matches the boundary that already exists.
[ADR-0006](../docs/adr/0006-lan-membership-is-the-auth-boundary.md).

**Do not port-forward or tunnel this.** That is layer 1 of the access model. If
you ever do put a tunnel in front of it, control switches itself off rather than
being handed to the internet — the peer-address check refuses commands from
non-private addresses, and `X-Forwarded-For` is never consulted because any
client can set it.

`Origin` and `Host` are validated on the WebSocket upgrade. That is not
belt-and-braces: DNS rebinding is the one route by which a page on the public
internet can reach a LAN-only service, through a browser that is itself on the
office network, and the network boundary offers no protection against it.

## When the office says the page is stuck

1. `curl http://<relay-host>:8080/health` — is the relay alive, and what state
   does it think the device is in?
2. `"state": "unreachable"` means the relay cannot see the speaker. Check the
   speaker is powered and on the network; the relay retries on its own with
   backoff and re-runs discovery after three failures.
3. `mDNS unavailable` in the logs means multicast is not working on the relay's
   host. Pass `--host <device-ip>` to bypass discovery entirely.
4. `"clients": 0` while someone has the page open means their browser is not
   reaching `/ws` — check they are on the office Wi-Fi and not on guest.
5. Restart: the relay is stateless. Nothing is lost by restarting it.

## Known limitation

Discovery has not been verified against the real device or the office network
yet — see SPIKE-05 in [the board](../docs/kanban/board.md). If the access points
have client isolation enabled, neither discovery nor the relay's connection will
work, and that needs a network change rather than a code change.
