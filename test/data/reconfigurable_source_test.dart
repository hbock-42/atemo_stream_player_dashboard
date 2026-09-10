/// CORE-04: switching mode rebuilds the source without restarting the app.
library;

import 'package:atemo_stream_player_viewer/config/app_config.dart';
import 'package:atemo_stream_player_viewer/config/app_config_controller.dart';
import 'package:atemo_stream_player_viewer/data/reconfigurable_source.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/manual_source.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a config change disposes the old source and starts one for the new config', () async {
    final built = <AppConfig>[];
    final sources = <ManualSource>[];
    final configs = AppConfigController();

    final source = ReconfigurableSource(
      initial: configs.config,
      configs: configs.changes,
      build: (config) {
        built.add(config);
        final next = ManualSource();
        sources.add(next);
        return next;
      },
    );
    final seen = <NowPlaying>[];
    source.stream.listen(seen.add);
    await source.start();

    sources.first.push(const Idle(deviceName: 'Office'));
    await configs.setMode(SourceMode.relay);
    await Future<void>.delayed(Duration.zero);

    expect(built.map((c) => c.mode), [SourceMode.direct, SourceMode.relay]);
    expect(sources.first.current, isA<NowPlaying>());
    // The replacement's state reaches the same stream the UI is already on.
    sources.last.push(const Idle(deviceName: 'Relayed'));
    await Future<void>.delayed(Duration.zero);

    expect(seen.whereType<Idle>().last.deviceName, 'Relayed');
    expect(seen.whereType<Connecting>(), isNotEmpty, reason: 'the swap is visible as reconnecting');

    await source.dispose();
    configs.dispose();
  });

  test('control follows the live source', () async {
    final configs = AppConfigController();
    final sources = <ManualSource>[];
    final source = ReconfigurableSource(
      initial: configs.config,
      configs: configs.changes,
      build: (config) {
        final next = ManualSource(controllable: config.mode == SourceMode.direct);
        sources.add(next);
        return next;
      },
    );
    await source.start();

    expect(source.control, isNotNull);
    await configs.setMode(SourceMode.relay);
    await Future<void>.delayed(Duration.zero);
    expect(source.control, isNull, reason: 'a read-only replacement must show as read-only');

    await source.dispose();
    configs.dispose();
  });

  test('dispose closes the inner source and stops listening to config', () async {
    final configs = AppConfigController();
    var builds = 0;
    final source = ReconfigurableSource(
      initial: configs.config,
      configs: configs.changes,
      build: (_) {
        builds++;
        return ManualSource();
      },
    );
    await source.start();
    await source.dispose();

    await configs.setMode(SourceMode.relay);
    await Future<void>.delayed(Duration.zero);

    expect(builds, 1);
    configs.dispose();
  });
}
