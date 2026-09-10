# ADR-0007 — The client ships to browsers only

**Status:** Accepted (user decision) · **Date:** 2026-09-10
**Narrows** [ADR-0005](0005-web-delivery-via-relay.md)

## Context

The Android and iOS targets were built and working: manifest permissions, an
Android multicast lock over a method channel, iOS Bonjour entitlements, launcher
icons, release signing, and an iOS CI job.

They were also, by ADR-0005, never the way anyone was going to use this. The
relay serves the web UI on the office network, so opening a URL is the whole
install process, and the add-to-home-screen manifest already covers wanting an
icon. Meanwhile the native targets carried real cost: an iOS distribution story
with no good answer under €99/yr, a keystore that must survive years, a macOS CI
job, and platform code that had to be kept working without anyone exercising it.

## Decision

Delete the `android/` and `ios/` directories. The Flutter app is built for the
web only. The relay, which is a Dart console app, is unaffected.

## What this removes

- `android/` and `ios/`, including the launcher icons and release signing config
- `lib/discovery/platform_multicast_lock.dart` — the Android method channel
- `tool/generate_icons.py` — it only generated native launcher icons; the web
  icons in `web/icons/` stand on their own
- The Android APK build, the `setup-java` step and the whole iOS job from CI

## What this does not remove

`lib/cast/`, `lib/domain/`, `lib/discovery/` and `DirectCastSource` all stay,
because **the relay runs them**. That is the point of their having no Flutter
imports. The mDNS discovery that finds the speaker now runs only on the relay
host, where no multicast lock is needed — that was an Android-only requirement.

`source_factory_io.dart` also stays: `flutter test` runs on the Dart VM, so the
io branch of the conditional export is what the test suite exercises.

## Consequences

- Cards DISC-02 (Android multicast lock), DISC-03 (iOS Bonjour entitlements) and
  POL-02 (native builds) are descoped rather than done. Their content is kept in
  the card files, so re-adding a native target is a matter of restoring platform
  directories rather than rediscovering the gotchas.
- The wall display (POL-01) is a browser in kiosk mode, which it already was —
  the wake lock is the Screen Wake Lock API, not a native plugin.
- CI is one job and materially faster: the APK build alone was 239s of a 401s
  run.
- If a native target ever returns, the multicast lock interface is still there
  with a no-op default, and this ADR records exactly what has to come back.
