/// Prefers a rich source and falls back to a poorer one that is more likely to
/// be available.
///
/// Built for CASTV2 over the mDNS status line: the connection gives title,
/// artist, album, artwork and control; the status line gives one string and
/// nothing else, but needs no connection and cannot be refused. When the
/// connection is up, the floor is not even polled. When it drops — device
/// refusing senders, the host unable to open a socket, a reconnect in progress
/// — the display degrades to the status line instead of going blank.
///
/// Composition rule, and the hysteresis that stops it flapping:
///
///   - The primary leads whenever it has something to show ([Playing], [Idle]).
///   - The floor is started only once the primary reports [Unreachable], and
///     stopped again as soon as the primary recovers. A brief [Connecting] on
///     the way to recovery keeps whatever was last shown.
///   - Control is the primary's, and only while the primary leads. The floor
///     never offers any.
library;

import 'dart:async';

import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import 'source_base.dart';

class CompositeSource with ReplayLatestSource implements NowPlayingSource {
  CompositeSource({
    required this.primary,
    required this.buildFloor,
    this.fallbackOnIdle = false,
  });

  final NowPlayingSource primary;

  /// When true, the primary reporting [Idle] also hands over to the floor — not
  /// just [Unreachable]. This is how a Spotify layer sits below CASTV2: the
  /// Cast connection reports Idle whenever a Connect protocol is playing
  /// (Spotify is invisible to it, OQ-1), and that Idle must be treated as "ask
  /// the next source", not "nothing is playing". Default false keeps the
  /// plain primary-plus-floor behaviour where Idle is authoritative.
  final bool fallbackOnIdle;

  /// A fresh floor each time it is needed. A source that owns a timer and a
  /// subprocess is disposed when the primary recovers, and a disposed source
  /// cannot be restarted — so the next outage builds another.
  final NowPlayingSource Function() buildFloor;

  StreamSubscription<NowPlaying>? _primarySub;
  StreamSubscription<NowPlaying>? _floorSub;
  NowPlayingSource? _floor;
  bool _primaryLeads = true;
  bool _disposed = false;

  /// Which source is currently on screen. Exposed for diagnostics and tests.
  bool get primaryLeads => _primaryLeads;

  @override
  PlaybackControl? get control => _primaryLeads ? primary.control : null;

  @override
  SourceMode get mode => primary.diagnostics.mode;

  @override
  SourceDiagnostics get diagnostics {
    final leading = _primaryLeads || _floor == null
        ? primary.diagnostics
        : _floor!.diagnostics;
    return leading.withFacts([
      DiagnosticFact('showing', _primaryLeads ? 'live connection' : 'mDNS status line'),
      if (!_primaryLeads) DiagnosticFact('connection', primary.diagnostics.lastError ?? '—'),
    ]);
  }

  @override
  Future<void> start() async {
    _primarySub ??= primary.stream.listen(_onPrimary);
    await primary.start();
  }

  void _onPrimary(NowPlaying state) {
    if (_disposed) return;
    switch (state) {
      case Playing():
        _primaryLeads = true;
        unawaited(_stopFloor());
        emit(state);
      case Idle():
        if (fallbackOnIdle) {
          // Cast sees nothing, but a lower source (Spotify) might. Consult it,
          // and let it decide between Playing and Idle.
          _primaryLeads = false;
          unawaited(_startFloor());
        } else {
          _primaryLeads = true;
          unawaited(_stopFloor());
          emit(state);
        }
      case Unreachable():
        // The primary is out. Hand over to the floor, which reports its own
        // state if it can still see — that is the honest answer, from whichever
        // source can still see.
        _primaryLeads = false;
        unawaited(_startFloor());
      case Connecting():
        // Nothing to show yet, or a reconnect behind a live screen. Keep what
        // is there.
        if (current is Connecting) emit(state);
    }
  }

  Future<void> _startFloor() async {
    if (_floor != null) return;
    final floor = buildFloor();
    _floor = floor;
    _floorSub = floor.stream.listen((state) {
      if (_disposed || _primaryLeads) return;
      // The floor cannot see a Connecting; anything it says is current.
      emit(state);
    });
    await floor.start();
  }

  Future<void> _stopFloor() async {
    final floor = _floor;
    if (floor == null) return;
    _floor = null;
    await _floorSub?.cancel();
    _floorSub = null;
    await floor.dispose();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _primarySub?.cancel();
    _primarySub = null;
    await _stopFloor();
    await primary.dispose();
    await closeController();
  }
}
