/// The seam.
///
/// Everything above this file is source-agnostic: the UI never learns whether
/// its data arrived over CASTV2 directly, through the relay, or from the
/// Spotify Web API.
library;

import 'diagnostics.dart';
import 'now_playing.dart';

/// Thrown when a control action cannot be performed — nothing is playing, the
/// casting app does not support it, or the connection is gone.
///
/// A domain-level type on purpose: `state/` reverts optimistic UI on this
/// without ever importing the protocol layer.
class PlaybackControlException implements Exception {
  const PlaybackControlException(this.message);

  /// Phrased for a person to read.
  final String message;

  @override
  String toString() => message;
}

/// Control over playback, when the source offers any.
///
/// Sources expose this as nullable rather than as a set of no-op methods, so
/// "this source cannot control anything" is a state the UI has to handle
/// rather than one it can forget about.
abstract interface class PlaybackControl {
  void play();
  void pause();
  void next();
  void previous();
  void seek(Duration position);
  void setVolume(double level);
  void setMuted(bool muted);
}

abstract interface class NowPlayingSource {
  /// Broadcast, and replays the latest value to new listeners.
  Stream<NowPlaying> get stream;

  /// The most recent state, for listeners that arrive late.
  NowPlaying get current;

  /// Null when this source is read-only.
  PlaybackControl? get control;

  /// How this source is doing, in source-agnostic terms.
  ///
  /// On the interface rather than on a side channel so the diagnostics screen
  /// can be handed any source at all — direct, relay or fake — and still say
  /// something true. [ReplayLatestSource] supplies a workable default derived
  /// from [current], so a source only overrides this if it knows more.
  SourceDiagnostics get diagnostics;

  Future<void> start();
  Future<void> dispose();
}
