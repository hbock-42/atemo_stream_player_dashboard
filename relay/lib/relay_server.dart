/// Holds the single CASTV2 connection and fans it out to browsers.
///
/// A browser cannot open the raw TLS socket CASTV2 requires, so this process
/// does it once on everyone's behalf — which also means the device only ever
/// sees one sender however many people are watching (ADR-0005).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing_source.dart';

import 'access.dart';

class RelayServer {
  RelayServer({
    required this.source,
    this.policy = const AccessPolicy(),
    this.webRoot,
    this.port = 8080,
    this.maxCommandsPerWindow = 20,
    this.commandWindow = const Duration(seconds: 5),
  });

  final NowPlayingSource source;
  final AccessPolicy policy;

  /// Directory holding `flutter build web` output. Null serves no UI.
  final Directory? webRoot;

  final int port;
  final int maxCommandsPerWindow;
  final Duration commandWindow;

  final Set<_Client> _clients = <_Client>{};
  final DateTime _startedAt = DateTime.now();

  HttpServer? _server;
  StreamSubscription<NowPlaying>? _subscription;
  NowPlaying _latest = const Connecting();

  int get clientCount => _clients.length;
  NowPlaying get latest => _latest;

  /// The port actually bound. Differs from [port] when 0 was requested.
  int? get boundPort => _server?.port;

  Future<void> start() async {
    await source.start();
    _subscription = source.stream.listen(_onState);

    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handle, onError: (Object error) => _log('http error: $error'));

    _log('listening on port ${server.port}');
    _log(webRoot == null
        ? 'no web root configured; serving the WebSocket only'
        : 'serving the web UI from ${webRoot!.path}');
    await _announceUrls(server.port);
  }

  /// Prints the addresses people should actually open.
  ///
  /// "Run the relay and give people the URL" is useless without knowing what
  /// the URL is, and it is different on every network.
  Future<void> _announceUrls(int port) async {
    if (webRoot == null) return;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final addresses = [
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ];

    stdout.writeln('');
    if (addresses.isEmpty) {
      stdout.writeln('  No LAN address found — is this machine on the Wi-Fi?');
    } else {
      stdout.writeln('  Share this with the office:');
      for (final address in addresses) {
        stdout.writeln('      http://$address:$port');
      }
      stdout.writeln('  Wall display:  http://${addresses.first}:$port/?wall');
    }
    stdout.writeln('  On this machine: http://localhost:$port');
    stdout.writeln('');
  }

  void _onState(NowPlaying state) {
    _latest = state;
    final payload = jsonEncode(state.toJson());
    for (final client in _clients.toList()) {
      client.send(payload);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final decision = policy.evaluate(request);
    if (!decision.allowed) {
      _log('refused ${request.connectionInfo?.remoteAddress.address}: ${decision.reason}');
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden: ${decision.reason}');
      await request.response.close();
      return;
    }

    if (request.uri.path == '/ws') {
      await _upgrade(request, decision);
      return;
    }
    if (request.uri.path == '/health') {
      await _health(request);
      return;
    }
    await _serveStatic(request);
  }

  Future<void> _upgrade(HttpRequest request, AccessDecision decision) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final client = _Client(
      socket: socket,
      canControl: decision.canControl,
      maxCommands: maxCommandsPerWindow,
      window: commandWindow,
    );
    _clients.add(client);
    _log('client connected (${_clients.length} total)');

    // Tell the client up front whether it may command, per ADR-0006. A client
    // that may not still gets state — viewing and controlling are separable.
    client
      ..send(jsonEncode({'type': 'hello', 'canControl': client.canControl}))
      ..send(jsonEncode(_latest.toJson()));

    socket.listen(
      (dynamic message) => _onCommand(client, message),
      onDone: () => _remove(client),
      onError: (Object _) => _remove(client),
      cancelOnError: true,
    );
  }

  void _remove(_Client client) {
    if (_clients.remove(client)) {
      _log('client disconnected (${_clients.length} remaining)');
    }
  }

  void _onCommand(_Client client, dynamic raw) {
    if (!client.canControl || raw is! String) return;
    if (!client.allowCommand()) {
      _log('rate-limited a client');
      return;
    }

    Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      envelope = decoded;
    } on FormatException {
      return;
    }

    final control = source.control;
    if (control == null) return;

    try {
      // A fixed set: LAUNCH and LOAD are not expressible here, so no client can
      // make the speaker play something of its own choosing.
      switch (envelope['command']) {
        case 'play':
          control.play();
        case 'pause':
          control.pause();
        case 'next':
          control.next();
        case 'previous':
          control.previous();
        case 'seek':
          final ms = envelope['positionMs'];
          if (ms is num) control.seek(Duration(milliseconds: ms.toInt()));
        case 'setVolume':
          final level = envelope['level'];
          if (level is num) control.setVolume(level.toDouble());
        case 'setMuted':
          final muted = envelope['muted'];
          if (muted is bool) control.setMuted(muted);
      }
    } on PlaybackControlException catch (error) {
      client.send(jsonEncode({'type': 'error', 'message': error.message}));
    }
  }

  Future<void> _health(HttpRequest request) async {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'state': _latest.toJson(),
        'clients': _clients.length,
        'uptimeSeconds': DateTime.now().difference(_startedAt).inSeconds,
      }));
    await request.response.close();
  }

  Future<void> _serveStatic(HttpRequest request) async {
    final root = webRoot;
    if (root == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final requested = request.uri.path == '/' ? '/index.html' : request.uri.path;
    final resolved = File('${root.path}$requested').absolute;

    // Refuse anything that escapes the web root.
    if (!resolved.path.startsWith(root.absolute.path)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final file = await resolved.exists()
        ? resolved
        // Single-page app: unknown paths fall back to the shell.
        : File('${root.path}/index.html');

    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.headers
      ..contentType = _contentTypeFor(file.path)
      // The bundle is versioned by filename; the shell must not be cached or a
      // redeploy leaves people on the old app.
      ..set(HttpHeaders.cacheControlHeader,
          file.path.endsWith('index.html') ? 'no-cache' : 'max-age=3600');

    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  static ContentType _contentTypeFor(String path) => switch (path.split('.').last) {
        'html' => ContentType.html,
        'js' || 'mjs' => ContentType('application', 'javascript', charset: 'utf-8'),
        'css' => ContentType('text', 'css', charset: 'utf-8'),
        'json' => ContentType.json,
        'wasm' => ContentType('application', 'wasm'),
        'png' => ContentType('image', 'png'),
        'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
        'svg' => ContentType('image', 'svg+xml'),
        'ico' => ContentType('image', 'x-icon'),
        'ttf' => ContentType('font', 'ttf'),
        'woff2' => ContentType('font', 'woff2'),
        _ => ContentType.binary,
      };

  void _log(String message) {
    // Structured enough to diagnose a 3am failure the next morning.
    stdout.writeln('${DateTime.now().toIso8601String()} relay: $message');
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    for (final client in _clients.toList()) {
      await client.close();
    }
    _clients.clear();
    await source.dispose();
    await _server?.close(force: true);
  }
}

class _Client {
  _Client({
    required this.socket,
    required this.canControl,
    required this.maxCommands,
    required this.window,
  });

  final WebSocket socket;
  final bool canControl;
  final int maxCommands;
  final Duration window;

  final List<DateTime> _recent = <DateTime>[];

  /// One misbehaving browser tab must not be able to flood the device.
  bool allowCommand() {
    final now = DateTime.now();
    _recent.removeWhere((at) => now.difference(at) > window);
    if (_recent.length >= maxCommands) return false;
    _recent.add(now);
    return true;
  }

  void send(String payload) {
    if (socket.readyState != WebSocket.open) return;
    socket.add(payload);
  }

  Future<void> close() async {
    try {
      await socket.close();
    } on Exception {
      // Already gone.
    }
  }
}
