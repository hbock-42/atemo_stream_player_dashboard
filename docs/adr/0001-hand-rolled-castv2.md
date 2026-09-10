# ADR-0001 — Hand-roll the CASTV2 client rather than use a pub.dev package

**Status:** Accepted · **Date:** 2026-09-10
**Amended 2026-09-10 by [ADR-0004](0004-bidirectional-control.md):** the app now sends
control commands as well as observing. The decision below is unchanged and its rationale
strengthened — see ADR-0004's "Why this does not change ADR-0001". Read "observer" below as
"adopts a session it did not launch", which is the property that actually matters.

## Context

We need a CASTV2 client in Dart. Candidates on pub.dev are `dart_chromecast` and `cast`.

## Decision

Hand-roll the protocol. Dependencies: `multicast_dns` (discovery) and
`web_socket_channel` (the relay client, which must work on web where
`dart:io`'s WebSocket does not exist). Nothing else.

**Amended during implementation:** `CastMessage` is hand-encoded rather than
generated, dropping the `protobuf` runtime dependency too. The message is six
fields of varint and length-delimited string; a codec plus its round-trip,
unknown-field and truncation tests came to under 200 lines, which is less than
the cost of vendoring generated code and a runtime to read it. Unknown fields
are skipped rather than rejected, so a firmware update that adds one does not
break us. `protoc` is consequently not required to build this project.

## Rationale

- **We adopt a session we did not launch.** Every published package models a *sender
  session*: discover, launch an app, push media, control it — tracking a `mediaSessionId`
  and `transportId` from its own `LAUNCH`. Our requirement is the inverse: attach to a
  session that already exists, and never `LAUNCH`, which would evict the office's live
  Spotify/Tidal playback. That adoption path is the one these libraries lack.
- **Surface area is small.** Length-prefix framing plus a six-field protobuf plus four
  namespaces is roughly 250 lines. That is below the threshold where a dependency pays.
- **The hard parts are ours anyway.** Heartbeat timing, app-change handling, reconnect
  backoff, tolerating malformed payloads from cheap hardware — no package gets these right
  for our device, and each is something we would have to override.
- **Maintenance risk.** Both candidates are thinly maintained. A stalled dependency in the
  one layer we cannot work around is the worst place to take that risk.
- **Portability.** Pure-Dart `cast/` with no Flutter import lifts unchanged into the relay
  server (ADR-0002) and runs under plain `dart test`.
- **Web build.** Both candidates import `dart:io` unconditionally. Our own `cast/` can be
  excluded from the web bundle via a conditional import; a dependency's transitive
  `dart:io` cannot. See [ADR-0005](0005-web-delivery-via-relay.md).

## Consequences

- We own protocol bugs. Mitigated by the fake device in `test/support/fake_cast_device.dart`,
  which scripts app changes, quits, silence, fragmented frames and malformed payloads, and
  by the existing Python `pychromecast` PoC as a reference oracle.
- No `.proto` file and no codegen step: `lib/cast/cast_message.dart` is the whole of it.

## Rejected

`dart_chromecast` — sender-oriented, unmaintained, bundles its own protobuf.
`cast` — closer to raw, but still session/control-shaped and thinly maintained.
