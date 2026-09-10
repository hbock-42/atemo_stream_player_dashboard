/// A [NowPlayingSource] that holds its own CASTV2 connection to the device.
///
/// Used by the native app, and by the relay — which is the same code running
/// headless, which is why `cast/` carries no Flutter import.
library;

import 'dart:async';

import '../cast/cast_client.dart';
import '../cast/cast_commands.dart';
import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import 'media_status_mapper.dart';
import 'source_base.dart';

class DirectCastSource with ReplayLatestSource implements NowPlayingSource {
  DirectCastSource({
    required CastAddressResolver resolveAddress,
    CastClient? client,
    this.mapper = const MediaStatusMapper(),
  }) : _client = client ?? CastClient(resolveAddress: resolveAddress) {
    _commands = CastCommands(_client);
    _control = _CastPlaybackControl(_commands);
  }

  final CastClient _client;
  final MediaStatusMapper mapper;
  late final CastCommands _commands;
  late final _CastPlaybackControl _control;
  StreamSubscription<CastUpdate>? _subscription;

  /// Bounded on purpose: this runs for days on the wall display.
  final DiagnosticLog _log = DiagnosticLog();
  LinkState _link = LinkState.connecting;
  String? _lastError;
  String? _lastLogged;

  @override
  PlaybackControl? get control => _control;

  CastClient get client => _client;

  @override
  SourceMode get mode => SourceMode.direct;

  /// Translates the protocol's own facts into the seam's vocabulary, so the
  /// diagnostics screen can show a transport id without ever importing
  /// `lib/cast/`: the id travels as a string, the labels as data.
  @override
  SourceDiagnostics get diagnostics {
    final snapshot = _client.snapshot;
    return SourceDiagnostics(
      mode: SourceMode.direct,
      link: _link,
      endpoint: _client.address?.toString(),
      lastError: _lastError,
      sessionId: snapshot.transportId,
      lastMessageAt: _client.lastMessageAt,
      facts: [
        if (snapshot.deviceName != null) DiagnosticFact('device', snapshot.deviceName!),
        DiagnosticFact('app', snapshot.appDisplayName ?? 'none'),
        DiagnosticFact('transport id', snapshot.transportId ?? '—'),
        DiagnosticFact('media session', snapshot.mediaSessionId?.toString() ?? '—'),
        DiagnosticFact(
          'supported commands',
          '0x${snapshot.supportedMediaCommands.toRadixString(16)}',
        ),
      ],
      log: _log.entries,
    );
  }

  /// Skips a line identical to the previous one, so a device that re-sends the
  /// same status every second cannot flush the whole buffer in a minute.
  void _note(String message) {
    if (message == _lastLogged) return;
    _lastLogged = message;
    _log.add(message);
  }

  @override
  Future<void> start() async {
    _subscription ??= _client.updates.listen(_onUpdate);
    await _client.start();
  }

  void _onUpdate(CastUpdate update) {
    switch (update) {
      case CastConnecting():
        _link = LinkState.connecting;
        _note('connecting to ${_client.address?.toString() ?? 'the device'}');
        // Only surface "connecting" if we have nothing better to show; a
        // reconnect behind a live screen should not blank it.
        if (current is Unreachable || current is Connecting) {
          emit(Connecting(deviceName: _client.snapshot.deviceName));
        }
      case CastSnapshotUpdate(:final snapshot):
        _link = LinkState.connected;
        _note('status: app=${snapshot.appDisplayName ?? 'none'} '
            'transport=${snapshot.transportId ?? '—'}');
        emit(mapper.map(snapshot));
      case CastDisconnected(:final reason):
        _link = LinkState.disconnected;
        _lastError = reason;
        _note('disconnected: $reason');
        emit(Unreachable(reason: reason));
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _commands.dispose();
    await _client.dispose();
    await closeController();
  }
}

class _CastPlaybackControl implements PlaybackControl {
  _CastPlaybackControl(this._commands);
  final CastCommands _commands;

  @override
  void play() => _guard(_commands.play);

  @override
  void pause() => _guard(_commands.pause);

  @override
  void next() => _guard(_commands.next);

  @override
  void previous() => _guard(_commands.previous);

  @override
  void seek(Duration position) => _guard(() => _commands.seek(position));

  @override
  void setVolume(double level) => _guard(() => _commands.setVolume(level));

  @override
  void setMuted(bool muted) => _guard(() => _commands.setMuted(muted));

  /// Translates protocol rejections into the domain's exception, so the state
  /// layer can revert optimistic UI without knowing what CASTV2 is.
  void _guard(void Function() action) {
    try {
      action();
    } on CastCommandRejectedException catch (error) {
      throw PlaybackControlException(error.message);
    }
  }
}
