import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

import 'package:atemo_stream_player_viewer/data/source_base.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing_source.dart';
import 'package:streamplayer_relay/relay_server.dart';
import 'package:test/test.dart';

class StubSource with ReplayLatestSource implements NowPlayingSource {
  final StubControl _control = StubControl();

  @override
  PlaybackControl? get control => _control;

  @override
  Future<void> start() async {}

  void push(NowPlaying state) => emit(state);

  @override
  Future<void> dispose() async => closeController();
}

class StubControl implements PlaybackControl {
  final List<String> calls = [];
  double? volume;

  @override
  void play() => calls.add('play');
  @override
  void pause() => calls.add('pause');
  @override
  void next() => calls.add('next');
  @override
  void previous() => calls.add('previous');
  @override
  void seek(Duration position) => calls.add('seek:${position.inMilliseconds}');
  @override
  void setVolume(double level) {
    volume = level;
    calls.add('setVolume');
  }

  @override
  void setMuted(bool muted) => calls.add('setMuted:$muted');
}

const track = Playing(
  title: 'Waltz for Debby',
  artist: 'Bill Evans Trio',
  castingApp: 'Spotify',
  volumeLevel: 0.4,
  capabilities: Capabilities(canPause: true),
);

void main() {
  _healthDiagnosticsTests();
  _readOnlySourceTests();
  _artworkProxyTests();
  late StubSource source;
  late RelayServer server;

  setUp(() async {
    source = StubSource();
    server = RelayServer(source: source, port: 0);
    await server.start();
  });

  tearDown(() => server.stop());

  Future<(WebSocket, StreamQueue)> connect() async {
    final socket = await WebSocket.connect('ws://127.0.0.1:${server.boundPort}/ws');
    return (socket, StreamQueue(socket.map((d) => jsonDecode(d as String))));
  }

  test('a new client is told whether it may control, then given state', () async {
    source.push(track);
    final (socket, messages) = await connect();

    final hello = await messages.next as Map<String, dynamic>;
    expect(hello['type'], 'hello');
    expect(hello['canControl'], isTrue, reason: 'a LAN client controls, per ADR-0006');

    final state = await messages.next as Map<String, dynamic>;
    expect(state['state'], 'playing');
    expect(state['title'], 'Waltz for Debby');

    await socket.close();
  });

  test('state changes reach every connected client', () async {
    final (socketA, a) = await connect();
    final (socketB, b) = await connect();
    for (final queue in [a, b]) {
      await queue.next; // hello
      await queue.next; // initial state
    }

    source.push(track);

    expect((await a.next as Map)['title'], 'Waltz for Debby');
    expect((await b.next as Map)['title'], 'Waltz for Debby');

    await socketA.close();
    await socketB.close();
  });

  test('the wire format is the domain model, not raw Cast payloads', () async {
    source.push(track);
    final (socket, messages) = await connect();
    await messages.next;

    final state = await messages.next as Map<String, dynamic>;
    expect(state.keys, contains('capabilities'));
    expect(state.keys, isNot(contains('mediaSessionId')));
    expect(state.keys, isNot(contains('supportedMediaCommands')));

    await socket.close();
  });

  test('commands are forwarded to the source', () async {
    source.push(track);
    final (socket, messages) = await connect();
    await messages.next;
    await messages.next;

    socket
      ..add(jsonEncode({'command': 'pause'}))
      ..add(jsonEncode({'command': 'setVolume', 'level': 0.62}))
      ..add(jsonEncode({'command': 'seek', 'positionMs': 5000}));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(source._control.calls, containsAll(['pause', 'setVolume', 'seek:5000']));
    expect(source._control.volume, 0.62);

    await socket.close();
  });

  test('LAUNCH and LOAD are not expressible in the envelope', () async {
    final (socket, messages) = await connect();
    await messages.next;
    await messages.next;

    // Even a fully authorised client cannot make the speaker play something
    // of its own choosing.
    socket
      ..add(jsonEncode({'command': 'LAUNCH', 'appId': 'CC1AD845'}))
      ..add(jsonEncode({'command': 'LOAD', 'media': {'contentId': 'http://evil/a.mp3'}}))
      ..add(jsonEncode({'command': 'stopSession'}));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(source._control.calls, isEmpty);

    await socket.close();
  });

  test('malformed frames are ignored rather than fatal', () async {
    final (socket, messages) = await connect();
    await messages.next;
    await messages.next;

    socket
      ..add('not json')
      ..add(jsonEncode([1, 2, 3]))
      ..add(jsonEncode({'command': 42}))
      ..add(jsonEncode({'command': 'setVolume', 'level': 'loud'}));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(source._control.calls, isEmpty);
    // Still alive and still serving.
    source.push(track);
    expect((await messages.next as Map)['title'], 'Waltz for Debby');

    await socket.close();
  });

  test('one client flooding is rate-limited, not passed through', () async {
    source.push(track);
    final server2 = RelayServer(
      source: source,
      port: 0,
      maxCommandsPerWindow: 5,
      commandWindow: const Duration(seconds: 5),
    );
    await server2.start();
    final socket = await WebSocket.connect('ws://127.0.0.1:${server2.boundPort}/ws');

    for (var i = 0; i < 50; i++) {
      socket.add(jsonEncode({'command': 'pause'}));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(source._control.calls.length, lessThanOrEqualTo(5),
        reason: 'a misbehaving tab must not flood the device');

    await socket.close();
    await server2.stop();
  });

  test('a disconnecting client does not disturb the others', () async {
    final (socketA, a) = await connect();
    final (socketB, b) = await connect();
    for (final queue in [a, b]) {
      await queue.next;
      await queue.next;
    }

    await socketA.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(server.clientCount, 1);

    source.push(track);
    expect((await b.next as Map)['title'], 'Waltz for Debby');

    await socketB.close();
  });

  test('health reports connection state and client count', () async {
    source.push(track);
    final (socket, _) = await connect();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final client = HttpClient();
    final response =
        await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/health')))
            .close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    client.close();

    expect(body['clients'], 1);
    expect(body['state']['state'], 'playing');

    await socket.close();
  });
}

void _artworkProxyTests() {
  group('artwork proxy', () {
    late StubSource source;
    late RelayServer server;

    setUp(() async {
      source = StubSource();
      server = RelayServer(source: source, port: 0);
      await server.start();
    });

    tearDown(() => server.stop());

    Future<Map<String, dynamic>> firstState() async {
      final socket = await WebSocket.connect('ws://127.0.0.1:${server.boundPort}/ws');
      final messages = StreamQueue(socket.map((d) => jsonDecode(d as String)));
      await messages.next; // hello
      final state = await messages.next as Map<String, dynamic>;
      await socket.close();
      return state;
    }

    test('device artwork is rewritten to this relay', () async {
      source.push(const Playing(
        title: 'A Track',
        artworkUrl: 'http://192.168.1.131:8008/art.jpg',
      ));

      final state = await firstState();

      // A speaker will never send CORS headers, and Flutter web fetches images
      // through CanvasKit — so a cross-origin URL simply does not load.
      expect(state['artworkUrl'], startsWith('/art?u='));
    });

    test('a public URL is proxied too, since CanvasKit needs CORS either way',
        () async {
      // A CDN may or may not send CORS; serving it from the relay makes the
      // question moot and works for every service.
      source.push(const Playing(
        title: 'A Track',
        artworkUrl: 'https://i.scdn.co/image/abc.jpg',
      ));

      expect((await firstState())['artworkUrl'], startsWith('/art?u='));
    });

    test('no artwork stays absent', () async {
      source.push(const Playing(title: 'A Track'));
      expect((await firstState())['artworkUrl'], isNull);
    });

    test('an un-advertised URL is refused, so this is not an open proxy', () async {
      // A client asking for a URL the relay never chose to proxy must be
      // turned away, or /art becomes a general-purpose fetcher.
      final url = base64Url.encode(utf8.encode('http://example.com/x.png'));
      final client = HttpClient();
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/art?u=$url')))
          .close();
      await response.drain<void>();
      client.close();

      expect(response.statusCode, HttpStatus.forbidden);
    });

    test('a malformed parameter is refused', () async {
      final client = HttpClient();
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/art?u=%%%')))
          .close();
      await response.drain<void>();
      client.close();

      // Undecodable, so certainly not in the allowlist — refused like any
      // other URL the relay did not advertise.
      expect(response.statusCode, HttpStatus.forbidden);
    });
  });
}

class ReadOnlySource with ReplayLatestSource implements NowPlayingSource {
  @override
  PlaybackControl? get control => null;
  @override
  Future<void> start() async {}
  void push(NowPlaying state) => emit(state);
  @override
  Future<void> dispose() async => closeController();
}

void _readOnlySourceTests() {
  group('a source with no control', () {
    test('tells clients so, even though the access policy would allow it', () async {
      // The mDNS status-line source can only read. Telling a browser it may
      // control anyway renders disabled buttons and a volume slider pinned at
      // zero — which reads as broken, when the truth is simply view-only.
      final source = ReadOnlySource();
      final server = RelayServer(source: source, port: 0);
      await server.start();
      addTearDown(server.stop);

      final socket = await WebSocket.connect('ws://127.0.0.1:${server.boundPort}/ws');
      final hello = jsonDecode(await socket.first as String) as Map<String, dynamic>;
      await socket.close();

      expect(hello['type'], 'hello');
      expect(hello['canControl'], isFalse);
    });
  });
}

void _healthDiagnosticsTests() {
  group('health diagnostics', () {
    test('reports the active source and its link state, for 3am debugging',
        () async {
      final source = StubSource();
      final server = RelayServer(source: source, port: 0);
      await server.start();
      addTearDown(server.stop);
      source.push(const Playing(title: 'A Track'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final client = HttpClient();
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/health')))
          .close();
      final body = jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      client.close();

      expect(body['source'], isA<Map<String, dynamic>>());
      final src = body['source'] as Map<String, dynamic>;
      expect(src.keys, containsAll(['mode', 'link', 'endpoint', 'lastError']));
      expect(src['link'], 'connected', reason: 'a Playing state means connected');
    });
  });
}
