# Running the spikes

Everything in EPIC-0 needs the real Streamplayer and the real office network.
This page is the whole procedure. Expect about two hours, most of it waiting.

The tooling is deliberately built on the **same `CastClient` the relay ships**,
so a spike that works is evidence about the code we actually run, not about a
separate probe that happens to work.

```bash
cd relay && dart pub get
```

> **On macOS, grant Local Network permission first.** System Settings → Privacy
> & Security → Local Network → enable your terminal app, then quit and reopen
> it. Without it every mDNS attempt fails with `No route to host` while
> `dns-sd` still works. See OQ-9.
>
> These must be run from a normal shell on the office network. They cannot be
> run from the development sandbox, which blocks outbound LAN sockets for
> interpreted processes — Dart and Python both get `No route to host` where
> `nc` succeeds.

---

## SPIKE-05 — the office network. **Do this first.**

```bash
tool/network_check.sh <ip-of-another-device-on-the-wifi>
```

Pass a colleague's laptop or phone address. Without it the client-isolation
check is skipped, and that is the check that matters: if the access points
isolate clients, phones cannot reach the relay and the relay may not reach the
speaker. That is a network change, not a code change, and everything else is
wasted effort until it is resolved.

The script also tells you the two things it cannot check itself: whether a guest
SSID can reach this subnet, and whether the router's UPnP could auto-expose the
relay.

Record under **OQ-8**.

---

## SPIKE-03 — does it keep advertising when idle?

```bash
cd relay && dart run bin/spike.dart discover --seconds 30
```

Run it three times: while playing, while idle, and after 30+ minutes idle. It
also reports whether port 8009 still answers when mDNS has gone quiet — which is
the answer that decides whether address caching (DISC-04) is required or merely
nice.

Record under **OQ-3**.

---

## SPIKE-01 — what actually surfaces on the media namespace?

```bash
cd relay && dart run bin/spike.dart probe --host <device-ip> --seconds 180
```

Read-only: it connects, watches, and prints the first occurrence of every
message type with its payload. It never sends a command and never launches an
app, so the session you are watching is undisturbed.

While it runs, play from **every service anyone here actually uses** — at least
Spotify, Tidal, Deezer and SoundCloud, plus anything else people reach for. For
each, record:

- does an application appear in `RECEIVER_STATUS`, and with what `displayName`?
- does `MEDIA_STATUS` arrive with real title/artist/album?
- what `supportedMediaCommands` value is reported?

Expect two different outcomes. Deezer and SoundCloud cast over Google Cast
proper, so they should launch a real receiver app and publish full metadata.
Spotify Connect and Tidal Connect are separate protocols and may publish
nothing at all. Confirm rather than assume — the two are indistinguishable from
the outside.

Run this in a second terminal at the same time:

```bash
cd relay && dart run bin/spike.dart txt --seconds 600
```

It polls the device's mDNS TXT record and prints `st=` and `rs=` whenever they
change. `rs=` carries a status line (`Casting: …`). **If it tracks the track for
every service**, that is a service-agnostic fallback needing no CASTV2
connection and no sender slot — worth far more than a per-service Web API,
which would need separate OAuth for each of the four. If it only tracks some,
record which.

Save the output. Those payloads become the fixtures in
`test/support/fake_cast_device.dart`.

Record under **OQ-1**.

---

## SPIKE-02 — how many senders before it misbehaves?

```bash
cd relay && dart run bin/spike.dart senders --host <device-ip> --max 16
```

**Music must be playing.** The outcome that matters is not the number at which
connections start failing — it is whether adding senders ever disturbs the
session that is actually playing. Watch the speaker, not the terminal.

Record under **OQ-2**.

---

## SPIKE-04 — will it take commands from a foreign sender?

```bash
cd relay && dart run bin/spike.dart commands --host <device-ip> --i-am-at-the-speaker
```

**This one changes what is playing** — it pauses, resumes, skips and moves the
volume on a real speaker in a real office. The flag is deliberate. Start
playback from a *different* device first, so we are genuinely testing a foreign
sender.

It reports, per command, whether the device confirmed it and how long that took.
Both halves matter: the confirmation latency is what sets the revert timeout in
`STATE-02`, currently guessed at 2s.

It restores the original volume when it finishes.

Record under **OQ-5**.

---

## Afterwards

1. Write the answers into [open-questions.md](open-questions.md).
2. Tick the acceptance boxes in `docs/kanban/cards/EPIC-0-spikes.md` and close
   the SPIKE issues.
3. If a service came back silent, EPIC-8 becomes real work — and its shape
   depends on *how many*. One silent service is a Web API source; several is an
   argument for the `rs=` route instead. If everything reported metadata, close
   EPIC-8 as not needed.
4. Anything that behaved differently from `docs/protocol.md` — fix the doc, and
   check whether `fake_cast_device.dart` should learn the same behaviour.
