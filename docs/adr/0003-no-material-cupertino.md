# ADR-0003 — No `material.dart`, no `cupertino.dart`

**Status:** Accepted (user constraint) · **Date:** 2026-09-10

## Decision

Root the app at `WidgetsApp`. Build every visual primitive from `widgets.dart`. Neither
`package:flutter/material.dart` nor `package:flutter/cupertino.dart` may be imported
anywhere in `lib/`, enforced by a lint and a CI grep.

## What this costs, concretely

`WidgetsApp` provides far less than `MaterialApp`. These are silent or ugly failures:

| Missing | Must supply |
|---|---|
| Text style | `DefaultTextStyle` with explicit `color` *and* `fontFamily`, or text renders with the yellow-on-red debug underline |
| Text direction | a `Directionality` ancestor |
| App colour | `color:` is a required argument on `WidgetsApp` |
| Safe areas | read `MediaQuery.paddingOf(context)` by hand; there is no `Scaffold` |
| Background | no `Scaffold`; paint a root `ColoredBox`/`DecoratedBox` |
| Routing | a `pageRouteBuilder` if any route is pushed. v1 is a single screen — prefer no navigation at all |
| Ripples, scrollbars, icons | none exist. Use `GestureDetector` + `AnimatedContainer` for feedback; ship icons as SVG paths or a bundled font |

## Consequences

- A small `ui/theme/` token layer (one `InheritedWidget`) and a `ui/widgets/` primitive
  layer are prerequisites for any screen work. Card [CORE-03].
- Fonts are bundled in `pubspec.yaml` rather than inherited from the platform.
- No third-party UI kit is introduced to fill the gap — that would reintroduce the
  dependency this constraint exists to avoid.
