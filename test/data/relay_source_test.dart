/// WEB-03 — a tab left open on a desk must be live in the morning.
///
/// Backoff alone is not enough: after a laptop sleeps for eight hours the
/// browser comes back and the socket is dead, and nobody wants to watch a
/// spinner for the remaining 30 seconds of a backoff schedule that was
/// designed for a relay that is down.
library;

import 'dart:convert';
import 'dart:math';

import 'package:atemo_stream_player_viewer/data/relay_source.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_browser.dart';
import '../support/fake_web_socket.dart';

void main() {
  late FakeBrowser browser;
  late List<FakeWebSocket> sockets;
  late RelaySource source;

  FakeWebSocket latest() => sockets.last;

  RelaySource build({Duration minReconnectInterval = Duration.zero}) {
    browser = FakeBrowser();
    sockets = [];
    return source = RelaySource(
      url: 'ws://streamplayer.local:8080/ws',
      random: Random(1),
      browser: browser,
      minReconnectInterval: minReconnectInterval,
      connect: (url) {
        final socket = FakeWebSocket(url);
        sockets.add(socket);
        return socket;
      },
    );
  }

  String playing(String title) => jsonEncode(
        Playing(title: title, capabilities: const Capabilities()).toJson(),
      );

  tearDown(() => source.dispose());

  test('a resumed browser reconnects immediately instead of waiting out the backoff',
      () async {
    await build().start();
    expect(sockets, hasLength(1));

    // The relay's socket died while the laptop was asleep.
    latest().dropped();
    await pumpEventQueue();
    expect(sockets, hasLength(1), reason: 'the backoff timer has not fired yet');

    browser.resume();
    await pumpEventQueue();
    expect(sockets, hasLength(2), reason: 'the browser came back; do not wait');

    latest().receive(playing('Waltz for Debby'));
    await pumpEventQueue();
    expect((source.current as Playing).title, 'Waltz for Debby');
  });

  test('a resume replaces a socket that only looks alive', () async {
    // iOS Safari freezes a backgrounded tab; on return the socket can be dead
    // at the far end without ever reporting onDone, and the screen would go on
    // showing last night's track.
    await build().start();
    latest().receive(playing('Stale'));
    await pumpEventQueue();

    browser.resume();
    await pumpEventQueue();
    expect(sockets, hasLength(2));
    expect(sockets.first.closed, isTrue, reason: 'the stale socket is dropped');

    // The relay sends current state on connect, so a reconnect is the refresh.
    latest().receive(playing('Fresh'));
    await pumpEventQueue();
    expect((source.current as Playing).title, 'Fresh');
  });

  test('a deliberate reconnect does not flash Unreachable over live state', () async {
    await build().start();
    final seen = <NowPlaying>[];
    source.stream.listen(seen.add);
    latest().receive(playing('Waltz for Debby'));
    await pumpEventQueue();

    browser.resume();
    await pumpEventQueue();

    expect(seen.whereType<Unreachable>(), isEmpty);
    expect(source.current, isA<Playing>());
  });

  test('a chatty browser cannot turn tab-switching into a reconnect loop', () async {
    await build(minReconnectInterval: const Duration(seconds: 30)).start();

    browser
      ..resume()
      ..resume()
      ..resume();
    await pumpEventQueue();

    expect(sockets, hasLength(1));
  });

  test('a dead connection still reconnects immediately, throttle or not', () async {
    await build(minReconnectInterval: const Duration(seconds: 30)).start();
    latest().dropped();
    await pumpEventQueue();

    browser.resume();
    await pumpEventQueue();

    expect(sockets, hasLength(2), reason: 'nothing is connected; nothing to protect');
  });

  test('dispose leaves no listener on the browser bridge', () async {
    await build().start();
    expect(browser.hasListener, isTrue);

    await source.dispose();

    expect(browser.hasListener, isFalse);
    expect(latest().closed, isTrue);
    // An injected bridge belongs to its caller.
    expect(browser.disposed, isFalse);
  });

  test('a resume after dispose does nothing', () async {
    await build().start();
    await source.dispose();

    browser.resume();
    await pumpEventQueue();

    expect(sockets, hasLength(1));
  });
}
