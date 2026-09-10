/// A [NowPlayingSource] that talks to the relay instead of the device.
///
/// The relay's wire format is the domain model as JSON — never raw Cast
/// payloads — so this client stays dumb and works identically on web and
/// native. See ADR-0005.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import 'source_base.dart';

class RelaySource with ReplayLatestSource implements NowPlayingSource {
  RelaySource({required this.url, Random? random}) : _random = random ?? Random() {
    _control = _RelayControl(this);
  }

  /// e.g. `ws://streamplayer.local:8080/ws`
  final String url;
  final Random _random;

  late final _RelayControl _control;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _failureStreak = 0;
  bool _disposed = false;

  /// The relay decides whether this client may command. Until it says so, and
  /// whenever it refuses, this is null and the UI renders view-only.
  bool _controlGranted = true;

  @override
  PlaybackControl? get control => _controlGranted ? _control : null;

  @override
  Future<void> start() async {
    if (_disposed) return;
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect('cannot reach the relay'),
        onDone: () => _scheduleReconnect('the relay closed the connection'),
        cancelOnError: true,
      );
    } on Exception {
      _scheduleReconnect('cannot reach the relay');
    }
  }

  void _onMessage(dynamic raw) {
    _failureStreak = 0;
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      // The relay tells us up front whether we may control, per ADR-0006.
      if (decoded['type'] == 'hello') {
        _controlGranted = decoded['canControl'] != false;
        return;
      }
      emit(NowPlaying.fromJson(decoded));
    } on FormatException {
      // A malformed frame from the relay is not worth dropping the connection
      // for; the next state message will correct the display.
    }
  }

  void _scheduleReconnect(String reason) {
    if (_disposed || _reconnectTimer != null) return;
    _teardown();
    emit(Unreachable(reason: reason));

    const schedule = [1, 2, 4, 8, 16, 30];
    final seconds = schedule[min(_failureStreak, schedule.length - 1)];
    _failureStreak++;
    _reconnectTimer = Timer(
      Duration(seconds: seconds, milliseconds: _random.nextInt(500)),
      () {
        _reconnectTimer = null;
        _connect();
      },
    );
  }

  void send(Map<String, dynamic> command) {
    final channel = _channel;
    if (channel == null) {
      throw const PlaybackControlException('not connected to the relay');
    }
    channel.sink.add(jsonEncode(command));
  }

  void _teardown() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _teardown();
    await closeController();
  }
}

class _RelayControl implements PlaybackControl {
  _RelayControl(this._source);
  final RelaySource _source;

  @override
  void play() => _source.send({'command': 'play'});

  @override
  void pause() => _source.send({'command': 'pause'});

  @override
  void next() => _source.send({'command': 'next'});

  @override
  void previous() => _source.send({'command': 'previous'});

  @override
  void seek(Duration position) =>
      _source.send({'command': 'seek', 'positionMs': position.inMilliseconds});

  @override
  void setVolume(double level) => _source.send({'command': 'setVolume', 'level': level});

  @override
  void setMuted(bool muted) => _source.send({'command': 'setMuted', 'muted': muted});
}
