/// A source the test drives by hand, so optimistic-control behaviour can be
/// exercised without any timing luck.
library;

import 'package:atemo_stream_player_viewer/data/source_base.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing_source.dart';

class ManualSource with ReplayLatestSource implements NowPlayingSource {
  ManualSource({bool controllable = true, this.throwOnCommand}) {
    _control = controllable ? RecordingControl(() => throwOnCommand) : null;
  }

  /// When set, every command throws this message — the "device refused it"
  /// case from SPIKE-04.
  String? throwOnCommand;

  RecordingControl? _control;

  @override
  PlaybackControl? get control => _control;

  RecordingControl get recorded => _control!;

  @override
  Future<void> start() async {}

  /// Pushes a state as if it arrived from the device.
  void push(NowPlaying state) => emit(state);

  @override
  Future<void> dispose() async => closeController();
}

class RecordingControl implements PlaybackControl {
  RecordingControl(this._error);

  final String? Function() _error;
  final List<String> calls = [];
  double? lastVolume;

  void _record(String name) {
    calls.add(name);
    final error = _error();
    if (error != null) throw PlaybackControlException(error);
  }

  @override
  void play() => _record('play');

  @override
  void pause() => _record('pause');

  @override
  void next() => _record('next');

  @override
  void previous() => _record('previous');

  @override
  void seek(Duration position) => _record('seek');

  @override
  void setVolume(double level) {
    lastVolume = level;
    _record('setVolume');
  }

  @override
  void setMuted(bool muted) => _record('setMuted');
}
