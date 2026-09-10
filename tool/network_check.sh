#!/usr/bin/env bash
# SPIKE-05 — characterise the office network.
#
# Run this ON THE OFFICE WI-FI, ideally from the machine you intend to use as
# the relay host. It answers the one question that can invalidate the whole
# architecture: whether the access points let devices talk to each other.
#
#   tool/network_check.sh [peer-ip]
#
# `peer-ip` is another device on the same Wi-Fi — a colleague's laptop, a
# phone. Without it the client-isolation check is skipped, and that is the
# check that matters most.
set -uo pipefail

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

peer="${1:-}"

head_ "This host"
iface=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
ip=$(ipconfig getifaddr "${iface:-en0}" 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
echo "  interface: ${iface:-unknown}"
echo "  address:   ${ip:-unknown}"
echo "  gateway:   ${gateway:-unknown}"
case "$ip" in
  10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) pass "on a private network" ;;
  "") fail "no address found — are you on Wi-Fi?" ;;
  *) warn "address is not RFC1918; the relay's access checks expect a private LAN" ;;
esac

head_ "1. AP client isolation — the one that can sink the whole approach"
if [ -z "$peer" ]; then
  warn "skipped: pass another device's IP as the first argument"
  echo "     Without this you do not know whether phones can reach the relay."
elif ping -c 3 -W 2000 "$peer" >/dev/null 2>&1; then
  pass "$peer answers ping — devices can see each other"
else
  fail "$peer does not answer ping"
  echo "     If that device is definitely on this Wi-Fi and awake, client"
  echo "     isolation is probably on. Then NOTHING here works: phones cannot"
  echo "     reach the relay and the relay may not reach the speaker. That is a"
  echo "     network change, not a code change. Stop and fix this first."
fi

head_ "2. Multicast / mDNS"
if command -v dns-sd >/dev/null 2>&1; then
  echo "  browsing _googlecast._tcp for 8s…"
  found=$( (dns-sd -B _googlecast._tcp local & sleep 8; kill %1) 2>/dev/null | tail -n +5 | awk '{print $NF}' | sort -u )
  if [ -n "$found" ]; then
    pass "Cast devices advertising:"; echo "$found" | sed 's/^/       /'
    echo "$found" | grep -qi 'Streamplayer' && pass "Streamplayer is among them" \
      || warn "no instance named Streamplayer-* — is the speaker powered on?"
  else
    fail "nothing advertising _googlecast._tcp"
    echo "     Either the speaker is off, or the APs filter multicast. The relay"
    echo "     can be pointed at a fixed IP with --host to work around this."
  fi
else
  warn "dns-sd not available; skipping (this is a macOS tool)"
fi

head_ "3. Is the relay port free?"
if lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
  warn "something already listens on 8080 — pick another port with --port"
else
  pass "8080 is free"
fi

head_ "4. Things you have to check yourself"
cat <<'NOTES'
  · Guest SSID. Is there one, and can it reach this subnet? If it can, then
    "everyone on the office Wi-Fi" (ADR-0006) quietly includes visitors and
    anyone ever given the guest password. If it is VLAN-isolated, no issue.
    Test: join the guest network on a phone and try to reach this host.

  · UPnP on the router. It must not be able to auto-expose the relay's port.
    Layer 1 of ADR-0006 depends on the relay being unreachable from outside.
    Check the router's admin page and turn UPnP off if it is on.

  · Relay host. Prefer something wired and always-on. Record what you pick.
NOTES

head_ "Record the answers in docs/open-questions.md under OQ-8, and tick SPIKE-05."
