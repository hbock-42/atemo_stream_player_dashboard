# EPIC-1 — Project foundation

**Goal:** a Flutter app that builds and runs on Android and iOS, contains no Material or
Cupertino, and has the theme and primitive layer that every screen depends on.

---

## CORE-01 — Flutter project scaffold, minimal deps

**As** the developer, **I want** a project skeleton with the agreed folder structure,
**so that** code lands in the right layer from the first commit.

**Acceptance**
- [ ] `flutter create` for android + ios only.
- [ ] Folders exist per [architecture.md](../../architecture.md): `cast/ discovery/ domain/
      data/ state/ ui/{theme,widgets,screens}`, each with a `README.md` naming its
      responsibility and its forbidden imports.
- [ ] `pubspec.yaml` dependencies are exactly `protobuf` and `multicast_dns`. Any addition
      needs a line in the ADR log.
- [ ] `analysis_options.yaml` with strict lints; `flutter analyze` is clean.
- [ ] `flutter run` shows a blank themed screen on a physical Android and iOS device.

**Size:** S

---

## CORE-02 — `WidgetsApp` shell with no Material or Cupertino

**As** the developer, **I want** the app rooted at `WidgetsApp`, **so that** the
no-Material constraint holds structurally rather than by discipline.

See [ADR-0003](../../adr/0003-no-material-cupertino.md).

**Acceptance**
- [ ] `main.dart` imports only `package:flutter/widgets.dart`.
- [ ] `WidgetsApp` configured with `color`, `title`, a root `builder`, and no
      `pageRouteBuilder` (single screen).
- [ ] `Directionality` and a `DefaultTextStyle` with explicit `color` and `fontFamily`
      are established above the app content.
- [ ] Root background painted explicitly — there is no `Scaffold`.
- [ ] Safe-area insets applied from `MediaQuery.paddingOf`; verified on a notched iPhone
      and a gesture-nav Android.
- [ ] No debug-underlined text anywhere.

**Size:** S

---

## CORE-03 — Theme tokens and UI primitives

**As** the developer, **I want** a token layer and a small set of primitives, **so that**
screens are composed rather than hand-painted each time.

**Acceptance**
- [ ] `AppTheme` `InheritedWidget` with colour, spacing and type tokens; `AppTheme.of`.
- [ ] Dark-first palette suited to a room display; explicit background, surface, text
      primary/secondary, accent, error.
- [ ] A bundled font declared in `pubspec.yaml`.
- [ ] Primitives in `ui/widgets/`: `AppText` (title/body/caption), `AppSurface`,
      `AppButton` (`GestureDetector` + `AnimatedContainer` for press feedback),
      `AppSpinner`, `AppIcon`, `AppSlider` (`GestureDetector` + `CustomPaint`).
- [ ] Every interactive primitive has an explicit **disabled** visual state. Capability
      gating ([CAST-07]) means controls are routinely unavailable, so this is load-bearing,
      not decorative.
- [ ] `AppSlider` handles drag, tap-to-position, and reports both live drag values and a
      final settled value, so [UI-08] can rate-limit sensibly.
- [ ] Primitives are pure `widgets.dart`; no third-party UI package.
- [ ] A dev-only gallery route or widget renders every primitive for eyeballing.

**Size:** M

---

## CORE-04 — App configuration

**As** a user on a network where discovery misbehaves, **I want** to point the app at an
address by hand, **so that** a flaky mDNS setup doesn't make the app useless.

**Acceptance**
- [ ] A `AppConfig` object: source mode (`direct` | `relay`), optional manual device IP,
      optional relay WebSocket URL.
- [ ] A `source_factory.dart` with a conditional export
      (`if (dart.library.js_interop)`) so the web build never references `dart:io`.
      The web factory returns `RelaySource` only. See
      [architecture.md](../../architecture.md#platform-split).
- [ ] Native defaults to `relay` when one is discoverable, falling back to `direct`.
      Web is always `relay` and takes its URL from the page origin ([WEB-02]) — no
      configuration at all on the primary path.
- [ ] Values persist across restarts (a small file; no `shared_preferences` dependency
      unless justified).
- [ ] Switching mode rebuilds the source without restarting the app.

**Size:** S
