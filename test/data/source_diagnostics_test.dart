/// The seam's default: every source can answer "how are you?" without each
/// one having to implement diagnostics from scratch.
library;

import 'package:atemo_stream_player_viewer/data/fake_source.dart';
import 'package:atemo_stream_player_viewer/domain/diagnostics.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/data/relay_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_source.dart';

void main() {
  _relayDiagnosticsTests();
  test('a source with no opinion still reports a truthful link state', () {
    final source = ManualSource();
    addTearDown(source.dispose);

    expect(source.diagnostics.link, LinkState.connecting);
    expect(source.diagnostics.mode, SourceMode.unknown);

    source.push(const Idle(deviceName: 'Streamplayer'));
    expect(source.diagnostics.link, LinkState.connected);

    source.push(Unreachable(reason: 'cannot reach the relay'));
    expect(source.diagnostics.link, LinkState.disconnected);
    expect(source.diagnostics.lastError, 'cannot reach the relay');
  });

  test('the fake source announces that it is fake', () async {
    final source = FakeSource(interval: const Duration(days: 1));
    addTearDown(source.dispose);
    await source.start();

    expect(source.diagnostics.mode, SourceMode.fake);
    expect(source.diagnostics.link, LinkState.connected);
  });
}

void _relayDiagnosticsTests() {
  group('RelaySource diagnostics', () {
    test('reports the relay mode and which relay it is talking to', () {
      final source = RelaySource(url: 'ws://streamplayer.local:8080/ws');
      addTearDown(source.dispose);

      final d = source.diagnostics;

      expect(d.mode, SourceMode.relay,
          reason: 'through the relay is the common case for the office; '
              'reporting "unknown" makes the screen useless to most people');
      expect(d.endpoint, 'ws://streamplayer.local:8080/ws');
      expect(d.facts.map((f) => f.label), contains('relay'));
    });

    test('says whether the relay granted control', () {
      final source = RelaySource(url: 'ws://host/ws');
      addTearDown(source.dispose);

      final control = source.diagnostics.facts
          .firstWhere((f) => f.label == 'control');
      expect(control.value, 'granted');
    });

    test('the report includes the relay endpoint', () {
      final source = RelaySource(url: 'ws://host:9/ws');
      addTearDown(source.dispose);

      expect(source.diagnostics.toReport(), contains('ws://host:9/ws'));
    });
  });
}
