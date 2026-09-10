/// Shared plumbing for [NowPlayingSource] implementations: a broadcast stream
/// that replays the latest value to each new listener, so a widget that
/// subscribes late still renders immediately.
library;

import 'dart:async';

import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';

mixin ReplayLatestSource implements NowPlayingSource {
  final StreamController<NowPlaying> controller = StreamController<NowPlaying>.broadcast();
  NowPlaying _current = const Connecting();

  @override
  NowPlaying get current => _current;

  /// Replays the latest value, then follows the live stream.
  ///
  /// Deliberately not an `async*` generator: a generator only subscribes to
  /// the underlying controller once its first yield has been consumed, so any
  /// value emitted in that window is dropped. Subscribing in `onListen`
  /// happens synchronously with the listener's own `listen()` call, which
  /// closes the gap.
  @override
  Stream<NowPlaying> get stream {
    late StreamController<NowPlaying> out;
    StreamSubscription<NowPlaying>? subscription;

    out = StreamController<NowPlaying>(
      onListen: () {
        out.add(_current);
        subscription = controller.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
      },
      onCancel: () async => subscription?.cancel(),
    );
    return out.stream;
  }

  /// Publishes [next], skipping identical consecutive values so the UI does
  /// not rebuild on a status message that changed nothing.
  void emit(NowPlaying next) {
    if (next == _current) return;
    _current = next;
    if (!controller.isClosed) controller.add(next);
  }

  /// Publishes without the equality check, for optimistic updates that must
  /// land even when they coincide with the current value.
  void emitForced(NowPlaying next) {
    _current = next;
    if (!controller.isClosed) controller.add(next);
  }

  /// What this source can say about itself knowing only the domain state.
  ///
  /// A source that tracks a real connection overrides this and fills in the
  /// address, the session id and the log; everything else still reports a
  /// truthful link state for free, which is what keeps the diagnostics getter
  /// from being a burden on every implementation.
  @override
  SourceDiagnostics get diagnostics => SourceDiagnostics(
        mode: mode,
        link: switch (current) {
          Connecting() => LinkState.connecting,
          Unreachable() => LinkState.disconnected,
          _ => LinkState.connected,
        },
        lastError: switch (current) {
          Unreachable(:final reason) => reason,
          _ => null,
        },
      );

  /// Overridden by sources that know which way they are talking to the device.
  SourceMode get mode => SourceMode.unknown;

  Future<void> closeController() async {
    if (!controller.isClosed) await controller.close();
  }
}
