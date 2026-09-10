/// A scripted source, so the whole UI is developable and testable with no
/// device on the network.
library;

import 'dart:async';

import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import 'source_base.dart';

class FakeSource with ReplayLatestSource implements NowPlayingSource {
  FakeSource({
    List<NowPlaying>? script,
    this.interval = const Duration(seconds: 4),
    this.loop = true,
    bool controllable = true,
  }) : script = script ?? defaultScript {
    _control = controllable ? _FakeControl(this) : null;
  }

  final List<NowPlaying> script;
  final Duration interval;
  final bool loop;

  _FakeControl? _control;
  Timer? _timer;
  int _index = 0;

  @override
  PlaybackControl? get control => _control;

  @override
  SourceMode get mode => SourceMode.fake;

  @override
  Future<void> start() async {
    if (script.isEmpty) return;
    emit(script.first);
    _index = 0;
    _timer ??= Timer.periodic(interval, (_) {
      _index++;
      if (_index >= script.length) {
        if (!loop) {
          _timer?.cancel();
          _timer = null;
          return;
        }
        _index = 0;
      }
      emit(script[_index]);
    });
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await closeController();
  }

  /// Covers the states worth eyeballing: a full card, a long title, absent
  /// artist and artwork, a partially-capable app, idle, and a failure.
  static List<NowPlaying> get defaultScript => [
        const Playing(
          title: 'Sixteen Going On Seventeen',
          artist: 'Bill Evans Trio',
          album: 'Waltz for Debby',
          artworkUrl: null,
          castingApp: 'Spotify',
          volumeLevel: 0.4,
          capabilities: Capabilities(
            canPause: true,
            canSeek: true,
            canSkipNext: true,
            canSkipPrevious: true,
          ),
          deviceName: 'Streamplayer',
        ),
        const Playing(
          title: 'Everything In Its Right Place (Remastered 2016 Anniversary Edition)',
          artist: null,
          album: 'Kid A',
          castingApp: 'Tidal',
          isPaused: true,
          volumeLevel: 0.4,
          capabilities: Capabilities(canPause: true),
          deviceName: 'Streamplayer',
        ),
        const Idle(deviceName: 'Streamplayer', volumeLevel: 0.4),
      ];
}

class _FakeControl implements PlaybackControl {
  _FakeControl(this._source);
  final FakeSource _source;

  @override
  void play() => _setPaused(false);

  @override
  void pause() => _setPaused(true);

  @override
  void next() {}

  @override
  void previous() {}

  @override
  void seek(Duration position) {}

  @override
  void setVolume(double level) {
    final state = _source.current;
    if (state is Playing) _source.emit(state.copyWith(volumeLevel: level));
    if (state is Idle) _source.emit(state.copyWith(volumeLevel: level));
  }

  @override
  void setMuted(bool muted) {
    final state = _source.current;
    if (state is Playing) _source.emit(state.copyWith(isMuted: muted));
    if (state is Idle) _source.emit(state.copyWith(isMuted: muted));
  }

  void _setPaused(bool paused) {
    final state = _source.current;
    if (state is Playing) _source.emit(state.copyWith(isPaused: paused));
  }
}
