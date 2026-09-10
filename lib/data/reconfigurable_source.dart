/// A [NowPlayingSource] that swaps its own implementation when the
/// configuration changes (CORE-04: "switching mode rebuilds the source without
/// restarting the app").
///
/// Doing it here rather than in `state/` keeps the controller ignorant of
/// configuration: from above, this is one source with one stream whose
/// contents happen to start arriving from somewhere else.
library;

import 'dart:async';

import '../config/app_config.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import 'source_base.dart';

typedef ConfiguredSourceFactory = NowPlayingSource Function(AppConfig config);

class ReconfigurableSource with ReplayLatestSource implements NowPlayingSource {
  ReconfigurableSource({
    required AppConfig initial,
    required Stream<AppConfig> configs,
    required ConfiguredSourceFactory build,
  })  : _config = initial,
        _configs = configs,
        _build = build;

  final Stream<AppConfig> _configs;
  final ConfiguredSourceFactory _build;

  AppConfig _config;
  NowPlayingSource? _inner;
  StreamSubscription<NowPlaying>? _innerSubscription;
  StreamSubscription<AppConfig>? _configSubscription;
  bool _disposed = false;

  /// Serialises rebuilds: two rapid config changes must not leave two live
  /// sources fighting over the same stream.
  Future<void> _pending = Future<void>.value();

  AppConfig get config => _config;

  @override
  PlaybackControl? get control => _inner?.control;

  @override
  Future<void> start() async {
    _configSubscription ??= _configs.listen(_onConfig);
    await _swapTo(_config);
  }

  void _onConfig(AppConfig next) {
    if (next == _config) return;
    _config = next;
    // Show the reconnection rather than freezing on state from a source that
    // is already gone.
    emit(const Connecting());
    _pending = _pending.then((_) => _swapTo(next));
  }

  Future<void> _swapTo(AppConfig config) async {
    await _closeInner();
    if (_disposed || config != _config) return;
    final source = _build(config);
    _inner = source;
    _innerSubscription = source.stream.listen(emit);
    await source.start();
  }

  Future<void> _closeInner() async {
    await _innerSubscription?.cancel();
    _innerSubscription = null;
    await _inner?.dispose();
    _inner = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _configSubscription?.cancel();
    _configSubscription = null;
    await _pending;
    await _closeInner();
    await closeController();
  }
}
