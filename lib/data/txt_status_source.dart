/// A [NowPlayingSource] that reads the device's mDNS TXT record instead of
/// connecting to it.
///
/// The Streamplayer broadcasts `st` (an app is running) and `rs` (a status line
/// such as `Casting: <track>`) to the whole network. This is how the Android
/// phones in the office already show what is playing without any of them
/// having started it — the Cast framework reads the same field.
///
/// What it buys, versus CASTV2:
///
///   - **No connection at all**, so no sender slot. However many people watch,
///     the device sees nobody, which makes the concurrent-sender question
///     (OQ-2) irrelevant on this path.
///   - **Every service**, whoever launched it. A service that publishes nothing
///     on the media namespace still appears here.
///
/// What it costs: one string. No artist, no album, no artwork, no position, and
/// no control at all — hence `control` is null and the UI renders view-only.
library;

import 'dart:async';

import '../discovery/mdns_discovery.dart';
import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import 'source_base.dart';

class TxtStatusSource with ReplayLatestSource implements NowPlayingSource {
  TxtStatusSource({
    MdnsDiscovery? discovery,
    this.interval = const Duration(seconds: 5),
  }) : _discovery = discovery ?? MdnsDiscovery();

  final MdnsDiscovery _discovery;

  /// mDNS is a broadcast, but reading it is a query, and the device is cheap.
  final Duration interval;

  Timer? _timer;
  bool _disposed = false;

  /// Always null: a TXT record is readable, not writable.
  @override
  PlaybackControl? get control => null;

  @override
  SourceMode get mode => SourceMode.unknown;

  @override
  Future<void> start() async {
    await _poll();
    _timer ??= Timer.periodic(interval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_disposed) return;
    final txt = await _discovery.readTxtRecord();
    if (_disposed) return;
    emit(txt.isEmpty
        ? Unreachable(reason: 'the Streamplayer is not advertising')
        : fromTxt(txt));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await closeController();
  }

  /// Maps a TXT record to a domain state. Pure, so it can be tested against
  /// records captured from the real device.
  static NowPlaying fromTxt(Map<String, String> txt) {
    final deviceName = _clean(txt['fn']);
    final status = _clean(txt['rs']);
    final appRunning = txt['st'] == '1';

    // `rs` carries a status line even when idle — "Ready to cast" and friends
    // mean nothing is playing, and must not be shown as a track title.
    final title = _titleFrom(status);

    if (!appRunning || title == null) {
      return Idle(deviceName: deviceName);
    }
    return Playing(
      title: title,
      castingApp: null,
      deviceName: deviceName,
      // Nothing here supports control, and saying otherwise would render
      // buttons that cannot work.
      capabilities: Capabilities.none,
    );
  }

  /// The track out of a status line, or null when the line means "idle".
  static String? _titleFrom(String? status) {
    if (status == null) return null;

    const idle = ['ready to cast', 'ready to play', 'idle', 'backdrop'];
    if (idle.contains(status.toLowerCase())) return null;

    // Observed form: "Casting: Dor Fodida". The prefix is the receiver's, not
    // part of the track.
    for (final prefix in ['casting:', 'playing:', 'now playing:']) {
      if (status.toLowerCase().startsWith(prefix)) {
        final rest = status.substring(prefix.length).trim();
        return rest.isEmpty ? null : rest;
      }
    }
    return status;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
