# Relay runbook (RELAY-04)

One page. If it's not here, it belongs in [relay/README.md](../README.md) (the
day-to-day reference) or an ADR (a decision), not here.

The relay is a single point of failure for the whole office. This document is
what makes running it unattended for weeks acceptable.

## Do not port-forward or tunnel this relay

**Never expose the relay to the internet: no port forward, no UPnP, no
Tailscale/Cloudflare/ngrok tunnel, nothing.** This is layer 1 of the access
model in [ADR-0006](../../docs/adr/0006-lan-membership-is-the-auth-boundary.md).
The relay has no application-level authentication — the office Wi-Fi *is* the
credential, matching the Streamplayer's own (lack of) security model. There is
no PIN behind this; removing layer 1 removes the only thing stopping the
internet from reaching it.

The deliberate consequence, so nobody is surprised by it later: if a tunnel is
ever put in front of the relay anyway (e.g. for remote viewing), **control
switches itself off rather than being handed to the internet.** Layer 2 in
`relay/lib/access.dart` checks the *actual socket peer* address, never
`X-Forwarded-For` (any client can set that header), so a tunnelled request
arrives from a non-private address and is refused. People behind the tunnel
would see the page but every button would silently fail. That is the intended
failure mode, not a bug to route around — if remote access is ever genuinely
wanted, it needs a real design change (see ADR-0006 "Consequences"), not a
tunnel bolted on.

## Which host

[SPIKE-05](../../docs/kanban/cards/EPIC-0-spikes.md) is where the office
network gets characterised and candidate hosts get identified with actual
uptime/wiring notes — that work has not landed yet as of this writing, so
"wired preferred" below is the general recommendation, not a confirmed choice
of machine. Whichever host is picked:

- **Prefer wired Ethernet over Wi-Fi** for the relay's own network link. It's
  the one machine every phone in the office depends on; don't add its own
  Wi-Fi flakiness on top of everyone else's.
- **It must stay powered and on 24/7.** A Mac mini already racked/shelved
  somewhere, or a Raspberry Pi, are the two candidates this repo ships service
  definitions for.
- **It does not need to be fast.** The relay holds one TLS socket, fans out
  small JSON messages, and serves a static bundle; a Pi is plenty.

Both a launchd plist (macOS) and a systemd unit (Linux/Raspberry Pi) are
provided in this directory so the choice doesn't block this card.

## Compiled binary, not `dart run`

Deploy the output of `dart compile exe`, not `dart run bin/relay.dart`.

- **Startup:** `dart run` re-analyses and JIT-warms the program on every
  launch; the compiled binary starts executing immediately. On a machine that
  reboots rarely this mostly matters for `KeepAlive`/`Restart=always` flapping
  during a real fault — you want the relay back up in under a second, not
  several.
- **No runtime dependency on the Dart SDK or pub cache.** `dart compile exe`
  produces a single self-contained native executable. The target machine
  needs nothing installed beyond what's already in the binary — no SDK
  version drift, no `pub get` ever running unattended, nothing to break weeks
  later because a cache got cleared.
- The only cost is a build step (`dart compile exe`, a couple of seconds) done
  once per deploy, on a machine that has the SDK — not on the relay host
  itself. `relay/deploy/build_and_deploy.sh` does this.

Verified in this worktree: `dart compile exe relay/bin/relay.dart -o
/tmp/relay_test` completes in under 2 seconds and the resulting binary starts
and serves `/health` correctly (see "What was verified" below).

## Install

### macOS (launchd)

```bash
# 1. Build and lay out the files (compiles the relay, builds the web bundle):
relay/deploy/build_and_deploy.sh /opt/streamplayer-relay

# 2. Install the service definition:
sudo cp relay/deploy/com.streamplayer.relay.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.streamplayer.relay.plist
sudo chmod 644 /Library/LaunchDaemons/com.streamplayer.relay.plist

# 3. Log rotation (newsyslog picks this up automatically, no restart needed):
sudo cp relay/deploy/streamplayer-relay.newsyslog.conf /etc/newsyslog.d/streamplayer-relay.conf

# 4. Start it now, and on every future boot:
sudo launchctl bootstrap system /Library/LaunchDaemons/com.streamplayer.relay.plist
```

A `LaunchDaemon` (not a per-user `LaunchAgent`) is used deliberately: it
starts at boot with nobody logged in, which matters for an office machine
that gets rebooted for an OS update overnight.

### Linux / Raspberry Pi (systemd)

```bash
# 1. Create a dedicated, unprivileged service user (once):
sudo useradd --system --no-create-home --shell /usr/sbin/nologin streamplayer

# 2. Build and lay out the files:
relay/deploy/build_and_deploy.sh /opt/streamplayer-relay
sudo chown -R streamplayer:streamplayer /opt/streamplayer-relay

# 3. Log directory and rotation:
sudo mkdir -p /var/log/streamplayer-relay
sudo chown streamplayer:streamplayer /var/log/streamplayer-relay
sudo cp relay/deploy/streamplayer-relay.logrotate /etc/logrotate.d/streamplayer-relay

# 4. Install and enable the service (enable = survives reboot):
sudo cp relay/deploy/streamplayer-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now streamplayer-relay
```

## Start / stop / restart

| Action | macOS | Linux |
|---|---|---|
| Start | `sudo launchctl bootstrap system /Library/LaunchDaemons/com.streamplayer.relay.plist` | `sudo systemctl start streamplayer-relay` |
| Stop | `sudo launchctl bootout system/com.streamplayer.relay` | `sudo systemctl stop streamplayer-relay` |
| Restart | `sudo launchctl kickstart -k system/com.streamplayer.relay` | `sudo systemctl restart streamplayer-relay` |
| Status | `sudo launchctl print system/com.streamplayer.relay` | `sudo systemctl status streamplayer-relay` |
| Deploy a new build | `relay/deploy/build_and_deploy.sh` then restart (above) | same |

The relay is stateless — restarting it loses nothing except the in-memory
client list, and browsers reconnect on their own (RELAY-03).

## Read the logs

| Where | macOS | Linux |
|---|---|---|
| stdout (structured, one line per event) | `/opt/streamplayer-relay/logs/relay.log` | `/var/log/streamplayer-relay/relay.log` or `journalctl -u streamplayer-relay -f` |
| stderr (crashes, unhandled errors) | `/opt/streamplayer-relay/logs/relay.err.log` | `/var/log/streamplayer-relay/relay.err.log` |

Both service definitions point logging at files outside the process, so a
3am crash-and-restart is still readable in the morning — `KeepAlive` /
`Restart=always` bringing the process back up does not touch the log files.
Rotation is handled by `newsyslog` (macOS, config in this directory) and
`logrotate` (Linux, config in this directory) so the log directory doesn't
grow unbounded over a multi-week run; on Linux, `journalctl -u
streamplayer-relay --since "3 hours ago"` also works if persistent journal
storage is enabled (`ls -d /var/log/journal` — if that directory doesn't
exist, `sudo mkdir -p /var/log/journal && sudo systemctl restart
systemd-journald` enables it).

Every log line is timestamped and prefixed `relay:` (see
`relay/lib/relay_server.dart` `_log` and `relay/bin/relay.dart`'s
`runZonedGuarded` handler), so `grep` by timestamp or by `relay: refused` /
`relay: unhandled` finds the relevant lines quickly.

## Health check

```bash
curl -s http://streamplayer.local:8080/health | python3 -m json.tool
```

(Swap in the static IP if `.local` isn't resolving — see below. From the
relay host itself, `curl -s http://127.0.0.1:8080/health` also works and
sidesteps mDNS/network questions entirely.)

Example response:

```json
{
  "state": {
    "state": "playing",
    "deviceName": "Streamplayer-ab12cd34..."
  },
  "clients": 3,
  "uptimeSeconds": 41213
}
```

How to read it:

| Field | Meaning |
|---|---|
| `state.state` | Device connection state: `connecting`, `playing`/`paused`/`idle` (connected, see `NowPlaying` variants), or `unreachable`. `unreachable` is the one to worry about - it means the relay cannot see the Streamplayer at all. |
| `state.deviceName` | The Cast device the relay is holding a session with, once connected. `null` while connecting or unreachable. |
| `clients` | How many browser/app WebSocket connections are currently attached. `0` while genuinely nobody has the page open is normal; `0` while someone insists they do have it open means their request isn't reaching the relay - wrong Wi-Fi, guest network, or a stale bookmark pointing at an old IP. |
| `uptimeSeconds` | Seconds since this process started. A small number when nobody restarted it on purpose is itself a diagnostic - it means it crashed and the service manager relaunched it. Cross-check against the logs at that timestamp. |

## "The page is stuck" - what to check, in order

1. **Is the relay process itself alive?** `curl .../health`. No response at
   all (connection refused/timeout) means the process or the whole host is
   down - check service status (table above), then whether the host is
   powered on and on the network.
2. **Is the device connection the problem?** `state.state: "unreachable"` in
   the health response means the relay is up but can't see the Streamplayer.
   Check the speaker is powered and on the network. The relay already retries
   with backoff and re-runs discovery after repeated failures - this is not
   something to intervene in unless it's been stuck for many minutes.
3. **Is it an mDNS problem?** `relay: mDNS unavailable (...)` in the logs
   means multicast isn't working on the relay's own host/network (this is
   expected on some networks - see SPIKE-05). Restart the relay with
   `--host <device-ip>` to bypass discovery entirely.
4. **Is it reaching the one specific browser?** `clients` in `/health` not
   matching the number of people who say they have the page open usually
   means those people are on a different network (guest Wi-Fi, cellular data)
   or have a bookmark pointing at a stale IP.
5. **When genuinely unsure, restart.** The relay is stateless (see "Start /
   stop / restart" above); nothing is lost.

## Address: `http://streamplayer.local:8080` and its fallback

This resolves [OQ-7](../../docs/open-questions.md#oq-7--does-the-relay-host-have-a-stable-name-on-the-office-network).

**Status: unverified.** Nobody on this project has tested mDNS resolution
against a real Android or iOS handset on the real office network yet - that
is explicitly [SPIKE-05](../../docs/kanban/cards/EPIC-0-spikes.md)'s and
OQ-7's job, not something verifiable from a development machine or CI. What
follows is how to test it and what to fall back to; treat the `.local` name
as *hoped for*, not *confirmed*, until someone runs these steps on real
phones on the office Wi-Fi.

### How to test

**iOS:** Safari (and most apps) resolve `.local` names via Bonjour/mDNS out
of the box - this has historically been reliable. Open
`http://streamplayer.local:8080/health` in Safari on an iPhone that's on the
office Wi-Fi (not cellular, not a VPN). A JSON response confirms it works.

**Android:** mDNS/NSD support is inconsistent across manufacturers and OS
versions and is the actual open question here - some devices, and some
versions of Chrome specifically, fail to resolve `.local` names even when the
network permits multicast. Test the same URL,
`http://streamplayer.local:8080/health`, in Chrome on at least two different
Android devices/OS versions if available, since a pass on one phone does not
generalise. If it fails, try a second browser (e.g. Firefox) on the same
device before concluding the name itself is broken, since some of the
inconsistency is per-browser rather than per-OS.

Record results (device model, OS version, browser, pass/fail) against OQ-7 in
`docs/open-questions.md` when this is actually run - a blank "unverified"
here is not meant to stay blank forever.

### Static IP fallback

If `.local` resolution is unreliable on the phones that actually matter (the
common failure mode is "works on iOS, flaky-to-broken on some Android"):

1. Give the relay host a static IP (DHCP reservation on the router, keyed to
   its MAC address, is preferable to a manually-configured static IP - it
   survives the host being reimaged without anyone having to remember to
   redo the network config).
2. Bookmark `http://<that-ip>:8080` instead of the `.local` name. This is
   what actually needs to be memorable/bookmarked in practice - "the page" as
   a saved bookmark works identically to office staff whether the address
   behind it is a hostname or an IP.
3. `--host <device-ip>` (for the *Streamplayer's* address, a separate
   concern from the relay's own address) is unrelated to this - don't
   confuse the two. This fallback is about how phones find the *relay*.

Nothing in the relay's code depends on `.local` working - `--host` and the
static-IP bookmark are already fully supported today. This is a network/DNS
question, not a code change.

## What was verified before this card was marked done

Run in this development environment (not the real office network or the
real Streamplayer device), see the relay's own tests and manual runs during
this change:

- `dart compile exe relay/bin/relay.dart -o /tmp/relay_test` compiles
  successfully in ~2s.
- The compiled binary starts, logs `mDNS unavailable (No route to host)`
  (expected - this machine has no multicast route) without crashing, and
  keeps serving.
- `curl http://127.0.0.1:<port>/health` returns the documented JSON shape
  from both the compiled binary and `dart run bin/relay.dart`.
- `cd relay && dart test` - 32 tests pass.
- `flutter test` from the repo root - 71 tests pass.
- `./tool/check_layers.sh` passes.
- The plist validates with `plutil -lint` and both shell scripts pass
  `bash -n`.

**Not verifiable from here, and explicitly out of scope for this change:**
mDNS resolution from a real Android or iOS handset (OQ-7/SPIKE-05), actual
behaviour of the office Wi-Fi (AP client isolation, guest SSID reachability -
also SPIKE-05), a real week-long soak against the real Streamplayer, and
which physical machine ends up hosting this (SPIKE-05's candidate list).
