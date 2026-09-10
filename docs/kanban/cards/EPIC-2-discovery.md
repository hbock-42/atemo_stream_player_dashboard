# EPIC-2 — Device discovery

**Goal:** find the Streamplayer on the LAN reliably on both platforms, and degrade
gracefully when mDNS is blocked.

---

## DISC-01 — mDNS browse for `_googlecast._tcp`

**As** a user, **I want** the app to find the speaker without me typing an address,
**so that** it just works when I open it.

**Acceptance**
- [ ] Browses `_googlecast._tcp.local` via `multicast_dns`, resolves SRV → host + port and
      A → IPv4.
- [ ] Filters instance names matching `Streamplayer-<32 hex>`; if several are found, the
      first is used and the rest are logged.
- [ ] Also reads the TXT record's `fn` (friendly name) for display, when present.
- [ ] Returns a `DiscoveredDevice(name, ip, port)`; port defaults to 8009 if absent.
- [ ] Discovery times out after 5s rather than hanging, and is cancellable.
- [ ] Verified against the real device on the office network.

**Size:** M

---

## DISC-02 — Android multicast lock and permissions

**As** an Android user, **I want** discovery to work on my phone, **so that** I see the
track like everyone else.

**Acceptance**
- [ ] `AndroidManifest.xml` declares `INTERNET`, `ACCESS_NETWORK_STATE`,
      `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- [ ] A `WifiManager.MulticastLock` is acquired before browsing and released after, via a
      small platform channel — held only during discovery, never for the app's lifetime.
- [ ] The lock is released even when discovery throws or is cancelled.
- [ ] Verified: discovery returns nothing without the lock and returns the device with it,
      on a real handset.

**Size:** M

---

## DISC-03 — iOS local network entitlements

**As** an iOS user, **I want** the permission prompt to appear and discovery to work,
**so that** the app isn't silently empty.

**Acceptance**
- [ ] `Info.plist` has `NSLocalNetworkUsageDescription` with a sentence a colleague would
      accept.
- [ ] `Info.plist` has `NSBonjourServices` listing `_googlecast._tcp`.
- [ ] The local-network prompt appears on first discovery on a real device.
- [ ] Denying the prompt produces the `Unreachable` state with a message naming local
      network permission, not a blank screen. (iOS gives no API to read this state — infer
      it from "discovery returned nothing on first run".)

**Size:** S

---

## DISC-04 — Cached address and manual fallback

**As** a user whose network blocks multicast, **I want** the app to still connect,
**so that** a router setting doesn't defeat the whole thing.

Required or optional depending on [SPIKE-03].

**Acceptance**
- [ ] The last successful address is persisted and tried immediately on launch, in parallel
      with a fresh discovery.
- [ ] A direct connection attempt to the cached address succeeding means we skip waiting on
      mDNS entirely — noticeably faster cold start.
- [ ] After three consecutive connection failures the cache is discarded and discovery
      re-run (DHCP moved the device).
- [ ] The manual IP from [CORE-04] takes precedence over both.

**Size:** S
