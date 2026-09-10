# ADR-0006 — LAN membership is the authorisation boundary

**Status:** Accepted · **Date:** 2026-09-10 · **Resolves** [OQ-6](../open-questions.md#oq-6--who-is-allowed-to-control-the-speaker)

## Context

With control shipped ([ADR-0004](0004-bidirectional-control.md)), someone must decide who
may press the buttons. The user's decision: **everyone on the office Wi-Fi may view and
control; nobody outside it may do either.** No PIN, no accounts, no per-user identity.

## Decision

The network is the credential. There is no application-level authentication.

Enforced in three layers, so that no single misconfiguration silently opens it up:

1. **Reachability.** The relay is never exposed to the internet — no port forwarding, no
   UPnP, no tunnel. This is the primary control.
2. **Peer address check.** The relay rejects command messages whose *actual socket peer*
   is not an RFC1918 private address. `X-Forwarded-For` is never trusted for this, being
   trivially spoofable. Consequence: if a tunnel is ever placed in front of the relay for
   remote viewing, control fails closed automatically rather than being granted to the
   internet. That matches the stated intent without relying on anyone remembering it.
3. **Origin and Host validation.** See below.

## Why this is proportionate

The Streamplayer has no authentication of its own. Anyone on the LAN can already control it
from any Cast-capable app on their phone, without our software existing. LAN-membership is
therefore *already* the device's security model; we are matching the existing boundary, not
widening it. Adding a PIN would create the impression of a control that the underlying
hardware does not actually provide.

The blast radius is also proportionate: the worst an attacker achieves is pausing office
music or changing its volume. `LAUNCH` and `LOAD` remain unrepresentable in the command
envelope ([RELAY-05]), so nobody can make the speaker play arbitrary audio through this app.

## DNS rebinding — the one real remote attack path

A LAN-only unauthenticated service is still reachable from the internet *through a browser
on the LAN*. An attacker's site can re-resolve its own domain to the relay's private IP,
and the visitor's browser will then issue requests to the relay from inside the network.
The network boundary provides no protection here.

Mitigation, required in [RELAY-05]:

- Validate the `Origin` header on the WebSocket upgrade against an allowlist of the relay's
  own origins. A cross-origin upgrade is rejected.
- Validate the `Host` header against expected hostnames and IPs. An unrecognised `Host`
  is rejected, which is what defeats the rebind.
- Requests with no `Origin` (non-browser clients such as the native app) are permitted only
  after the peer-address check in layer 2.

## Consequences

- [RELAY-05]'s authorisation hook has a concrete default implementation rather than an
  open "everyone may".
- Read-only mode ([UI-09]) is no longer reachable via authorisation — every permitted client
  gets control. It remains reachable when a *source* offers none, e.g. a Spotify source
  without the modify scope, so the card stays.
- The office's Wi-Fi topology now matters to correctness. [SPIKE-05] characterises it:
  whether a guest SSID shares the subnet (which would make "everyone on the Wi-Fi" broader
  than intended), and whether AP client isolation is enabled (which would break the whole
  approach).
- Revisit if the office network stops being a trust boundary — a busy guest network, or a
  desire for genuine remote access. The single hook in RELAY-05 is where a PIN would go.
