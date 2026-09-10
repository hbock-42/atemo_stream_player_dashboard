# Architecture

## Principle

Three layers, one seam. The UI knows about `NowPlaying` and `PlaybackControl` and nothing
else. Everything Cast-specific lives below `NowPlayingSource` and can be replaced wholesale
— by a relay client, by the Spotify Web API, by a fake — without touching a widget.

```
        ┌──────────────────────────────────────────┐
        │  ui/            WidgetsApp, screens,     │
        │                 hand-built primitives    │
        └──────┬────────────────────────▲──────────┘
     commands  │                        │ listens to
        ┌──────▼────────────────────────┴──────────┐
        │  state/         NowPlayingController     │
        │                 (ChangeNotifier)         │
        └──────┬────────────────────────▲──────────┘
               │ PlaybackControl        │ Stream<NowPlaying>
        ╔══════▼════════════════════════┴══════════╗
        ║  domain/  NowPlayingSource  ← THE SEAM   ║
        ╚══════┬═══════════════════════════════════╝
             ┌─┴─────────────┬───────────────┬──────────────┐
   DirectCastSource    RelaySource   SpotifyWebApiSource  FakeSource
        (io only)      (io + web)                          (dev/tests)
             │
        ┌────┴──────────────────────────────┐
        │  cast/     CastClient             │  pure Dart, zero Flutter imports
        │            CastCommands           │  never LAUNCH, never LOAD
        │            CastChannel (TLS)      │
        │            cast_message.pb.dart   │
        └────┬──────────────────────────────┘
             │
        ┌────┴──────────────────────────────┐
        │  discovery/  mDNS + multicast lock│
        └───────────────────────────────────┘

  config/     persisted settings + last known address (shared_preferences)
  platform/   browser-only capabilities behind a conditional import
```

## The seam

```dart
abstract interface class NowPlayingSource {
  Stream<NowPlaying> get stream;
  NowPlaying get current;
  PlaybackControl? get control;      // null when this source is read-only
  SourceDiagnostics get diagnostics; // what this source can say about itself
  Future<void> start();
  Future<void> dispose();
}

abstract interface class PlaybackControl {
  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setVolume(double level);   // 0.0 – 1.0, device-level
  Future<void> setMuted(bool muted);
}
```

`control` is nullable rather than a set of no-op methods, so "this source cannot control
anything" is a state the UI must handle explicitly instead of one it can forget about.

State is a sealed model, never a nullable bag of fields:

```dart
sealed class NowPlaying {}
final class Connecting  extends NowPlaying { final String? deviceName; }
final class Playing     extends NowPlaying {
  final String? title, artist, album, artworkUrl, castingApp;
  final bool isPaused;
  final Duration? position, duration;
  final double? volumeLevel;          // device volume, from receiver status
  final bool isMuted;
  final Capabilities capabilities;    // decoded supportedMediaCommands
}
final class Idle        extends NowPlaying { final String? deviceName; final double? volumeLevel; }
final class Unreachable extends NowPlaying { final String reason; final DateTime since; }
```

`Idle` (device found, nothing playing) and `Unreachable` (device not found or socket dead)
are deliberately distinct — the user asked for visibly different states, and conflating them
is the most common bug in this class of app. Note that `Idle` still carries volume: the
device volume control works with no app running.

## Two ways to know what is playing

`DirectCastSource` opens a CASTV2 connection and gets everything: title, artist,
album, artwork, position, capabilities, and control.

`TxtStatusSource` reads the device's mDNS TXT record and gets one string — the
`rs=` status line, `Casting: <track>` — with no connection at all. It is how the
office Android phones already display what is playing without any of them having
started it.

The trade is stark and worth stating, because it is not obvious which is better
in every case:

| | CASTV2 | mDNS TXT |
|---|---|---|
| Metadata | title, artist, album, artwork, position | one status string |
| Control | yes, capability-gated | none — `control` is null |
| Sender slots used | one | zero |
| Concurrent-viewer limit | the device's, unknown (OQ-2) | none |
| Services that publish nothing on the media namespace | invisible | still visible |

The relay runs one or the other today (`--txt` selects the second). Composing
them — CASTV2 when it has metadata, TXT as the floor — is the obvious next step
and is deliberately not built until the spikes say which services need it.

## Diagnostics without leaking Cast

The diagnostics screen needs protocol-level facts — the transport id, how long
the device has been silent — but `ui/` may never import `cast/`. Those facts
therefore travel as `SourceDiagnostics` on the domain seam: a mode, a link
state, an endpoint, a last error, and a list of already-labelled
`DiagnosticFact`s plus a bounded log.

Sources fill in what they know. `DirectCastSource` reads its `CastClient`;
`RelaySource` reports the relay URL and whether the relay granted it control;
the mixin default derives a truthful link state from the domain state alone, so
adding the getter cost every other implementation nothing. The UI prints
label/value pairs it does not interpret, which is what keeps Cast vocabulary
below the seam.

## Optimistic control

A command's effect arrives as an unsolicited `MEDIA_STATUS` some hundreds of milliseconds
later. The controller therefore:

1. applies the intended state immediately, so the button feels responsive,
2. reconciles against the next real status message,
3. reverts if no confirming status arrives within ~2 seconds.

Volume is the case that matters most — a slider dragged against round-trip latency without
this is unusable.

## Module responsibilities

| Module | Owns | Must not |
|---|---|---|
| `cast/cast_channel.dart` | TLS socket, 4-byte length framing, `badCertificateCallback`, read buffer | Know what a track is |
| `cast/cast_client.dart` | Handshake order, heartbeat, request-id correlation, app-change, reconnect | Import Flutter |
| `cast/cast_commands.dart` | The five command families, capability checks | Ever emit `LAUNCH` or `LOAD` |
| `discovery/` | `_googlecast._tcp` browse, `Streamplayer-*` filter, Android multicast lock | Cache stale IPs silently |
| `data/media_status_mapper.dart` | `MEDIA_STATUS` + `RECEIVER_STATUS` → `NowPlaying` | Throw on unexpected shapes |
| `state/` | Lifecycle, retry policy, optimistic control, one value for the UI | Contain protocol knowledge |
| `config/` | Persisted settings and the stored device address | Be reachable from `cast/` |
| `platform/` | Browser capabilities behind a conditional import — visibility, online, wake lock | Exist on the native path |
| `ui/` | Rendering, layout, theming, capability-gated controls | Know the word "Cast" |

`cast/` and `domain/` are pure Dart with no Flutter dependency, so they run under plain
`dart test` and lift into the relay server unchanged.

## Topology

**The relay is mandatory** ([ADR-0005](adr/0005-web-delivery-via-relay.md)). Browsers cannot
open the raw TLS socket CASTV2 requires, so any browser-delivered UI needs a process on the
LAN to hold the connection on its behalf.

```
Streamplayer ──TLS:8009── [ relay ]  ──HTTP──> Flutter Web bundle
   one connection                    ──WS────> NowPlaying JSON + commands
```

The client is web-only ([ADR-0007](adr/0007-web-only-client.md)), so the relay is the only
thing that ever speaks CASTV2. `DirectCastSource` and `discovery/` are not dead code — they
are what the relay runs.

- **Web clients** (the default way in): `RelaySource`. Zero configuration — the page derives
  its socket URL from its own origin, since the relay served it. `?wall` on that URL enters
  the wall-display mode.
- **Native clients**: either mode, chosen in `AppConfig`. Direct is useful for a wall display
  that must survive the relay being down, and for development.
- The relay's wire format is `NowPlaying` serialised to JSON — the domain model, never raw
  Cast payloads. Protocol translation is the relay's job; clients stay dumb.

## Platform split

`DirectCastSource` depends on `dart:io` and cannot exist in a web build. So does anything
that reaches it transitively — `cast_address.dart` once imported `cast_channel.dart` for a
single constant, which quietly dragged `dart:io` into everything holding an address. It sits
behind a conditional import:

```dart
// data/source_factory.dart
export 'source_factory_io.dart' if (dart.library.js_interop) 'source_factory_web.dart';
```

The web factory returns only `RelaySource`. CI builds for web to prove nothing has dragged
`dart:io` back into the bundle.

## UI without Material

Root is `WidgetsApp`, which supplies far less than `MaterialApp`. Things that must be
provided explicitly, and are silent or ugly failures if forgotten:

- `color:` on `WidgetsApp` (required argument, used by the OS task switcher)
- a `Directionality` ancestor
- a `DefaultTextStyle` with an explicit `color` **and** `fontFamily` — without it text
  renders with the yellow/red debug underline
- safe-area insets from `MediaQuery.paddingOf(context)`, by hand
- `pageRouteBuilder` if any route is pushed. v1 is a single screen — prefer none

Theming is one `AppTheme` `InheritedWidget` holding colour and type tokens. Primitives live
in `ui/widgets/`, built from `DecoratedBox`, `Padding`, `GestureDetector`, `AnimatedOpacity`,
`Image` and `RichText`. Controls need a hand-built slider (`GestureDetector` +
`CustomPaint`) and hand-built buttons with an explicit disabled state, since capability
gating means controls are routinely unavailable.
