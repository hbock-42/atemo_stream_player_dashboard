/// CORE-04: changes persist immediately and are broadcast so the source can be
/// rebuilt without a restart.
library;

import 'package:atemo_stream_player_viewer/config/app_config.dart';
import 'package:atemo_stream_player_viewer/config/app_config_controller.dart';
import 'package:atemo_stream_player_viewer/config/config_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load applies what the last session saved', () async {
    await ConfigStore().save(const AppConfig(mode: SourceMode.relay, relayUrl: 'ws://host/ws'));

    final controller = AppConfigController();
    await controller.load();

    expect(controller.config.mode, SourceMode.relay);
    expect(controller.config.relayUrl, 'ws://host/ws');
    controller.dispose();
  });

  test('a mode change is announced and persisted', () async {
    final controller = AppConfigController();
    final seen = <AppConfig>[];
    controller.changes.listen(seen.add);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setMode(SourceMode.relay);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
    expect(seen.single.mode, SourceMode.relay);
    expect((await ConfigStore().load()).mode, SourceMode.relay);
    controller.dispose();
  });

  test('setting the same value again changes nothing and notifies nobody', () async {
    final controller = AppConfigController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setMode(SourceMode.direct);

    expect(notifications, 0);
    controller.dispose();
  });

  test('an emptied manual host is cleared, not stored as blank', () async {
    final controller = AppConfigController();
    await controller.setManualHost('10.0.0.7');
    await controller.setManualHost('  ');

    expect(controller.config.manualHost, isNull);
    expect((await ConfigStore().load()).manualHost, isNull);
    controller.dispose();
  });

  test('a manual host is trimmed before it reaches the socket layer', () async {
    final controller = AppConfigController();
    await controller.setManualHost(' 10.0.0.7 ');

    expect(controller.config.manualHost, '10.0.0.7');
    controller.dispose();
  });

  test('the relay URL persists too', () async {
    final controller = AppConfigController();
    await controller.setRelayUrl('ws://streamplayer.local:8080/ws');

    expect((await ConfigStore().load()).relayUrl, 'ws://streamplayer.local:8080/ws');
    controller.dispose();
  });
}
