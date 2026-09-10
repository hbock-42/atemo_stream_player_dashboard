/// The seam's default: every source can answer "how are you?" without each
/// one having to implement diagnostics from scratch.
library;

import 'package:atemo_stream_player_viewer/data/fake_source.dart';
import 'package:atemo_stream_player_viewer/domain/diagnostics.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_source.dart';

void main() {
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
