# CASTV2 — what we implement

Transport: TLS over TCP, port **8009**. Self-signed certificate; verification must be
bypassed via `badCertificateCallback` on `SecureSocket.connect`.

## Framing

```
┌───────────────────────┬───────────────────────────────┐
│ 4 bytes, big-endian   │ protobuf CastMessage          │
│ length of payload     │ (length bytes)                │
└───────────────────────┴───────────────────────────────┘
```

Reads are a stream of bytes, not of messages: the channel must buffer and only emit a
frame once `buffer.length >= 4 + prefix`. Multiple frames arrive in one TCP read, and a
single frame arrives split across reads. Both cases happen in practice.

`CastMessage` fields we use: `protocol_version` (0), `source_id`, `destination_id`,
`namespace`, `payload_type` (STRING), `payload_utf8`. Payloads are JSON strings.

Our `source_id` is a stable per-connection id, e.g. `sender-<random>`.

## Namespaces

| Namespace | Use |
|---|---|
| `urn:x-cast:com.google.cast.tp.connection` | `CONNECT`, `CLOSE` |
| `urn:x-cast:com.google.cast.tp.heartbeat` | `PING`, `PONG` |
| `urn:x-cast:com.google.cast.receiver` | `GET_STATUS` → `RECEIVER_STATUS` |
| `urn:x-cast:com.google.cast.media` | `GET_STATUS` → `MEDIA_STATUS` |

## Handshake

1. TLS connect to `<deviceIp>:8009`.
2. `CONNECT` on the connection namespace → `receiver-0`.
3. `GET_STATUS` on the receiver namespace → `receiver-0`. Response `RECEIVER_STATUS`
   carries `status.applications[0]` with `sessionId`, `transportId`, `displayName`,
   `appId`, `namespaces`.
4. `CONNECT` on the connection namespace → that `transportId`.
5. `GET_STATUS` on the media namespace → that `transportId`.
6. **Do not poll.** The device pushes `MEDIA_STATUS` unprompted on track changes.
7. Answer every `PING` with a `PONG` on the heartbeat namespace (arrives ~every 5s).
   Miss them and the device drops the connection.

We additionally send our own `PING` on a timer as a liveness probe, and treat "no traffic
of any kind for 15s" as a dead socket.

## Reading now-playing

`MEDIA_STATUS` → `status[0]`:

- `media.metadata.title`, `.artist` (or `.albumArtist`), `.albumName`
- `media.metadata.images[0].url` → artwork
- `playerState`: `PLAYING` | `PAUSED` | `BUFFERING` | `IDLE`
- `currentTime`, `media.duration`
- The casting app's display name comes from the **receiver** status, not this payload.

Every one of these fields is optional. The mapper must tolerate absence, wrong types and
empty arrays without throwing — a malformed payload from a €99 device must degrade to a
partial card, never to a crash.

## States to handle explicitly

| Situation | Signal | Result |
|---|---|---|
| Nothing playing | `RECEIVER_STATUS` with no `applications`, or `displayName == "Backdrop"` | `Idle` |
| App changed (Spotify → Tidal) | new `RECEIVER_STATUS` with different `transportId` | close old virtual connection, redo steps 4–5 |
| App quit | `RECEIVER_STATUS` loses the application | `Idle` |
| Socket dropped / device power-cycled | socket error or done | `Unreachable`, then reconnect with backoff |
| Device not on network | mDNS yields nothing | `Unreachable` |

Reconnect policy: exponential backoff 1s → 2s → 4s → 8s → 16s → 30s cap, with jitter,
resetting on a successful handshake. Re-run discovery (do not reuse a cached IP) after
three consecutive failures — DHCP will eventually move the device.

## Commands we send

See [ADR-0004](adr/0004-bidirectional-control.md).

### Device volume — the reliable one

On `urn:x-cast:com.google.cast.receiver` to `receiver-0`:

```json
{"type": "SET_VOLUME", "volume": {"level": 0.42}, "requestId": N}
{"type": "SET_VOLUME", "volume": {"muted": true}, "requestId": N}
```

This is device-level and works regardless of which app is casting, or whether any app is.
The response is a `RECEIVER_STATUS` carrying the new `volume`. It is the one control we can
count on even if [OQ-1](open-questions.md) resolves badly.

Volume is a float 0.0–1.0. Send absolute levels, and rate-limit a dragging slider to roughly
one message per 100ms — the device is cheap hardware and will not thank you for sixty.

### Transport — capability-gated

On `urn:x-cast:com.google.cast.media` to the `transportId`, each carrying the
`mediaSessionId` from the latest `MEDIA_STATUS`:

```json
{"type": "PAUSE",       "mediaSessionId": M, "requestId": N}
{"type": "PLAY",        "mediaSessionId": M, "requestId": N}
{"type": "QUEUE_NEXT",  "mediaSessionId": M, "requestId": N}
{"type": "QUEUE_PREV",  "mediaSessionId": M, "requestId": N}
{"type": "SEEK",        "mediaSessionId": M, "currentTime": 42.0, "requestId": N}
```

A command sent without a current `mediaSessionId` is dropped client-side rather than sent.

### `supportedMediaCommands`

`MEDIA_STATUS` carries this integer bitmask. **Gate the UI on it** — render unsupported
controls disabled rather than firing commands that silently do nothing. Commonly:

| Bit | Meaning |
|---|---|
| 1 | PAUSE |
| 2 | SEEK |
| 4 | STREAM_VOLUME |
| 8 | STREAM_MUTE |
| 64 | QUEUE_NEXT |
| 128 | QUEUE_PREV |

[SPIKE-04] verifies these against the actual device before we rely on them. Note bit 4 is
*stream* volume over the media namespace; device volume over the receiver namespace is a
separate and more reliable mechanism — prefer it.

### Confirming a command

There is no per-command acknowledgement to rely on. The effect arrives as an unsolicited
`MEDIA_STATUS` or `RECEIVER_STATUS`. Apply the change optimistically, reconcile on the next
status, revert if nothing confirms within ~2s.

## What we never send

`LAUNCH` and `LOAD`. Launching an application would evict whatever the office is currently
listening to. `STOP` is implemented but never surfaced in the UI — too easy to mis-tap, and
recovery needs the phone that started the session. Enforced by [TEST-03].
