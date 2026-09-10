/// Holds the app's single piece of state and owns the source's lifecycle.
///
/// Also implements optimistic control: a command's effect arrives as an
/// unsolicited status message some hundreds of milliseconds later, so the
/// intent is applied immediately, reconciled against the next real status, and
/// reverted if nothing confirms it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';

typedef SourceFactory = NowPlayingSource Function();

class NowPlayingController extends ChangeNotifier with WidgetsBindingObserver {
  NowPlayingController({
    required this.createSource,
    this.revertAfter = const Duration(seconds: 2),
    this.errorVisibleFor = const Duration(seconds: 4),
  });

  final SourceFactory createSource;

  /// How long to wait for a status message confirming a command before
  /// assuming it was ignored. Measured against the real device in SPIKE-04.
  final Duration revertAfter;

  final Duration errorVisibleFor;

  NowPlayingSource? _source;
  StreamSubscription<NowPlaying>? _subscription;
  Timer? _revertTimer;
  Timer? _errorTimer;

  NowPlaying _actual = const Connecting();
  NowPlaying _displayed = const Connecting();
  String? _lastError;
  String? _lastRefusedCommand;

  bool _draggingVolume = false;
  double? _dragVolume;
  bool _disposed = false;

  NowPlaying get value => _displayed;

  /// Null control means view-only: the source offers no control at all.
  bool get canControl => _source?.control != null;

  /// A message to show briefly when a command was refused.
  String? get lastError => _lastError;

  /// The current source's health, for the diagnostics screen.
  ///
  /// Goes through the seam: the controller has no idea whether the source
  /// underneath is a socket to the device or a websocket to the relay, and
  /// neither does the screen that renders this.
  SourceDiagnostics get diagnostics {
    final base = _source?.diagnostics ??
        const SourceDiagnostics(link: LinkState.disconnected, lastError: 'no source');
    final refused = _lastRefusedCommand;
    // Sticky, unlike [lastError], which fades from the main screen after a few
    // seconds: on a diagnostics screen "what was refused" outlives its toast.
    return refused == null
        ? base
        : base.withFacts([DiagnosticFact('last refused command', refused)]);
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await _open();
  }

  Future<void> _open() async {
    await _close();
    if (_disposed) return;
    final source = createSource();
    _source = source;
    _subscription = source.stream.listen(_onSourceState);
    await source.start();
  }

  Future<void> _close() async {
    _revertTimer?.cancel();
    _revertTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _source?.dispose();
    _source = null;
  }

  /// Rebuilds the source from scratch. Backing off automatically already
  /// happens underneath; this is the user saying "try now".
  Future<void> retry() async {
    _set(const Connecting());
    await _open();
  }

  void _onSourceState(NowPlaying next) {
    _actual = next;
    // A command has been confirmed (or contradicted) by real state.
    _revertTimer?.cancel();
    _revertTimer = null;
    _set(_preservingDrag(next));
  }

  /// While the user is dragging, their volume wins over anything arriving from
  /// the device — otherwise the slider fights the status stream.
  NowPlaying _preservingDrag(NowPlaying state) {
    if (!_draggingVolume || _dragVolume == null) return state;
    return switch (state) {
      Playing() => state.copyWith(volumeLevel: _dragVolume),
      Idle() => state.copyWith(volumeLevel: _dragVolume),
      _ => state,
    };
  }

  void _set(NowPlaying next) {
    if (_disposed) return;
    _displayed = next;
    notifyListeners();
  }

  // --- control ---------------------------------------------------------------

  void play() => _command(() => _source?.control?.play(), _withPaused(false));

  void pause() => _command(() => _source?.control?.pause(), _withPaused(true));

  void next() => _command(() => _source?.control?.next(), null);

  void previous() => _command(() => _source?.control?.previous(), null);

  void toggleMute() {
    final state = _displayed;
    final muted = switch (state) {
      Playing(:final isMuted) => isMuted,
      Idle(:final isMuted) => isMuted,
      _ => false,
    };
    _command(
      () => _source?.control?.setMuted(!muted),
      switch (state) {
        Playing() => state.copyWith(isMuted: !muted),
        Idle() => state.copyWith(isMuted: !muted),
        _ => null,
      },
    );
  }

  void beginVolumeDrag() {
    _draggingVolume = true;
  }

  void setVolume(double level) {
    _dragVolume = level;
    // Show the new position immediately; the device catches up.
    final state = _displayed;
    final optimistic = switch (state) {
      Playing() => state.copyWith(volumeLevel: level),
      Idle() => state.copyWith(volumeLevel: level),
      _ => null,
    };
    if (optimistic != null) _set(optimistic);
    try {
      _source?.control?.setVolume(level);
    } on PlaybackControlException catch (error) {
      _showError(error.message);
    }
  }

  void endVolumeDrag(double level) {
    _draggingVolume = false;
    _dragVolume = null;
    try {
      _source?.control?.setVolume(level);
    } on PlaybackControlException catch (error) {
      _showError(error.message);
      _revertNow();
    }
  }

  NowPlaying? _withPaused(bool paused) {
    final state = _displayed;
    return state is Playing ? state.copyWith(isPaused: paused) : null;
  }

  void _command(void Function() action, NowPlaying? optimistic) {
    if (optimistic != null) {
      _set(optimistic);
      _revertTimer?.cancel();
      // Nothing confirmed the command; put the true state back rather than
      // leaving a button lying about what the speaker is doing.
      _revertTimer = Timer(revertAfter, _revertNow);
    }
    try {
      action();
    } on PlaybackControlException catch (error) {
      _showError(error.message);
      _revertNow();
    }
  }

  void _revertNow() {
    _revertTimer?.cancel();
    _revertTimer = null;
    _set(_preservingDrag(_actual));
  }

  void _showError(String message) {
    _lastError = message;
    _lastRefusedCommand = message;
    notifyListeners();
    _errorTimer?.cancel();
    _errorTimer = Timer(errorVisibleFor, () {
      _lastError = null;
      if (!_disposed) notifyListeners();
    });
  }

  // --- lifecycle -------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // iOS will kill a backgrounded socket regardless; doing it ourselves
        // makes the reconnect deliberate instead of a surprise.
        unawaited(_close());
      case AppLifecycleState.resumed:
        if (_source == null) unawaited(_open());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _errorTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }
}
