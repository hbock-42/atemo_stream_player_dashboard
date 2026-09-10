/// CORE-04: the settings survive a restart. DISC-04: so does the address.
library;

import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/config/app_config.dart';
import 'package:atemo_stream_player_viewer/config/config_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a saved config comes back from a fresh store, as it would after a restart', () async {
    await ConfigStore().save(
      const AppConfig(
        mode: SourceMode.relay,
        manualHost: '192.168.1.50',
        relayUrl: 'ws://streamplayer.local:8080/ws',
      ),
    );

    final restarted = await ConfigStore().load();
    expect(restarted.mode, SourceMode.relay);
    expect(restarted.manualHost, '192.168.1.50');
    expect(restarted.relayUrl, 'ws://streamplayer.local:8080/ws');
  });

  test('an empty store yields the defaults', () async {
    expect(await ConfigStore().load(), const AppConfig());
  });

  test('clearing a field removes it rather than storing an empty string', () async {
    final store = ConfigStore();
    await store.save(const AppConfig(manualHost: '10.0.0.7'));
    await store.save(const AppConfig());

    expect((await ConfigStore().load()).manualHost, isNull);
  });

  test('an unrecognised mode falls back instead of throwing at startup', () async {
    SharedPreferences.setMockInitialValues({kConfigModeKey: 'spotify'});

    expect((await ConfigStore().load()).mode, SourceMode.direct);
  });

  test('the cached address round-trips, port and friendly name included', () async {
    await ConfigStore().writeCachedAddress(
      const CastAddress(host: '10.0.0.7', port: 8009, friendlyName: 'Office'),
    );

    final address = await ConfigStore().readCachedAddress();
    expect(address, const CastAddress(host: '10.0.0.7', port: 8009));
    expect(address!.friendlyName, 'Office');
  });

  test('clearing the cached address leaves nothing to try on the next launch', () async {
    final store = ConfigStore();
    await store.writeCachedAddress(const CastAddress(host: '10.0.0.7'));
    await store.clearCachedAddress();

    expect(await store.readCachedAddress(), isNull);
  });

  test('the AddressCache view writes through to the same store', () async {
    final store = ConfigStore();
    await store.addressCache.write(const CastAddress(host: '10.0.0.7'));

    expect(await store.readCachedAddress(), const CastAddress(host: '10.0.0.7'));

    await store.addressCache.clear();
    expect(await store.addressCache.read(), isNull);
  });
}
