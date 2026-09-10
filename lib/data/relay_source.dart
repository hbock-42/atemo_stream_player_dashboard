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

import '../domain/diagnostics.dart';
import '../domain/now_playing.dart';
import '../domain/now_playing_source.dart';
import '../platform/browser.dart';
import 'source_base.dart';

class RelaySource with ReplayLatestSource implements NowPlayingSource {
  RelaySource({
    required this.url,
    Random? random,
    WebSocketChannel Function(Uri url)? connect,
    BrowserBridge? browser,
    this.minReconnectInterval = const Duration(seconds: 2),
  })  : _random = random ?? Random(),
        _openChannel = connect ?? WebSocketChannel.connect,
        _ownsBrowser = browser == null,
        _browser = browser ?? createBrowserBridge() {
    _control = _RelayControl(this);
    // WEB-03. Backoff is right for a relay that is down; it is wrong for a
    // laptop that just woke up, where the network came back at a moment the
    // browser can tell us about and waiting out 30 seconds of backoff is
    // pointless. Off web this stream never fires.
    _resumeSubscription = _browser.resumed.listen((_) => reconnectNow());
  }

  /// e.g. `ws://streamplayer.local:8080/ws`
  final String url;

  /// Floor on browser-triggered reconnects, so a browser that is chatty with
  /// visibility events cannot turn tab-switching into a reconnect loop.
  final Duration minReconnectInterval;

  final Random _random;
  final WebSocketChannel Function(Uri url) _openChannel;
  final BrowserBridge _browser;
  final bool _ownsBrowser;

  late final _RelayControl _control;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<void>? _resumeSubscription;
  Timer? _reconnectTimer;
  final Stopwatch _sinceConnect = Stopwatch();
  int _failureStreak = 0;
  bool _disposed = false;

  /// The relay decides whether this client may command. Until it says so, and
  /// whenever it refuses, this is null and the UI renders view-only.
  bool _controlGranted = true;

  @override
  PlaybackControl? get control => _controlGranted ? _control : null;

  @override
  SourceMode get mode => SourceMode.relay;

  /// Adds what only this source knows: which relay it is talking to, and
  /// whether the relay has granted it control. Without these the diagnostics
  /// screen reports an unknown mode and no endpoint when reached through the
  /// relay, which is the common case for everyone in the office.
  @override
  SourceDiagnostics get diagnostics => super.diagnostics.copyWith(
        endpoint: url,
        facts: [
          DiagnosticFact('relay', url),
          DiagnosticFact('control', _controlGranted ? 'granted' : 'view only'),
        ],
      );

  @override
  Future<void> start() async {
    if (_disposed) return;
    _connect();
  }

  /// Reconnects immediately, whatever the backoff schedule had planned.
  ///
  /// Called when the browser says the page is in front of a human again. The
  /// socket is replaced even when it *looks* alive: a tab that iOS Safari
  /// froze comes back holding a socket that is dead at the other end but will
  /// never report `onDone`, and the screen would sit there showing last
  /// night's track. The relay sends `hello` plus current state on connect, so
  /// a reconnect is also the cheapest possible refresh.
  ///
  /// No [Unreachable] is emitted on this path: the display keeps showing what
  /// it had until real state arrives, which is what makes a resume invisible.
  void reconnectNow() {
    if (_disposed) return;
    if (_channel != null &&
        _sinceConnect.isRunning &&
        _sinceConnect.elapsed < minReconnectInterval) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // A human is watching again, so start the backoff schedule from the top.
    _failureStreak = 0;
    _teardown();
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    _sinceConnect
      ..reset()
      ..start();
    try {
      final channel = _openChannel(Uri.parse(url));
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
    _sinceConnect.stop();
    await _resumeSubscription?.cancel();
    _resumeSubscription = null;
    // Only tear down a bridge we created: an injected one is the caller's.
    if (_ownsBrowser) _browser.dispose();
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
