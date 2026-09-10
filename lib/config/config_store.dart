/// Persistence for [AppConfig] and for the last address the device answered on.
///
/// `shared_preferences` rather than a file of our own because it is backed by
/// `localStorage` on web and by the platform store everywhere else, so one
/// implementation covers every build we ship and `config/` needs no
/// conditional import (CORE-04, DISC-04).
///
/// This is the only part of the config layer that touches Flutter; the value
/// types it reads and writes are plain Dart, which keeps `data/` — and the
/// relay that lifts it — free of a Flutter dependency.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../cast/cast_address.dart';
import '../data/address_cache.dart';
import 'app_config.dart';

/// Namespaced so a future setting cannot collide with a plugin's own keys.
const String kConfigModeKey = 'config.sourceMode';
const String kConfigManualHostKey = 'config.manualHost';
const String kConfigRelayUrlKey = 'config.relayUrl';
const String kCachedHostKey = 'device.lastHost';
const String kCachedPortKey = 'device.lastPort';
const String kCachedNameKey = 'device.lastName';

class ConfigStore {
  ConfigStore({SharedPreferences? preferences}) : _preferences = preferences;

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// Falls back to [fallback] per field, so a half-written store (or a first
  /// launch) still yields a usable config instead of an error.
  Future<AppConfig> load({AppConfig fallback = const AppConfig()}) async {
    final prefs = await _prefs();
    return AppConfig(
      mode: sourceModeFromName(prefs.getString(kConfigModeKey)) ?? fallback.mode,
      manualHost: prefs.getString(kConfigManualHostKey) ?? fallback.manualHost,
      relayUrl: prefs.getString(kConfigRelayUrlKey) ?? fallback.relayUrl,
    );
  }

  Future<void> save(AppConfig config) async {
    final prefs = await _prefs();
    await prefs.setString(kConfigModeKey, config.mode.name);
    await _writeOrRemove(prefs, kConfigManualHostKey, config.manualHost);
    await _writeOrRemove(prefs, kConfigRelayUrlKey, config.relayUrl);
  }

  /// An [AddressCache] over the same store, for `data/` to use without ever
  /// learning what `shared_preferences` is.
  AddressCache get addressCache => _PrefsAddressCache(this);

  Future<CastAddress?> readCachedAddress() async {
    final prefs = await _prefs();
    final host = prefs.getString(kCachedHostKey);
    if (host == null || host.isEmpty) return null;
    return CastAddress(
      host: host,
      port: prefs.getInt(kCachedPortKey) ?? kDefaultCastPort,
      friendlyName: prefs.getString(kCachedNameKey),
    );
  }

  Future<void> writeCachedAddress(CastAddress address) async {
    final prefs = await _prefs();
    await prefs.setString(kCachedHostKey, address.host);
    await prefs.setInt(kCachedPortKey, address.port);
    await _writeOrRemove(prefs, kCachedNameKey, address.friendlyName);
  }

  Future<void> clearCachedAddress() async {
    final prefs = await _prefs();
    await prefs.remove(kCachedHostKey);
    await prefs.remove(kCachedPortKey);
    await prefs.remove(kCachedNameKey);
  }

  /// Removing rather than storing "" keeps "never set" and "set to nothing"
  /// from becoming the same value on the next read.
  Future<void> _writeOrRemove(SharedPreferences prefs, String key, String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

class _PrefsAddressCache implements AddressCache {
  const _PrefsAddressCache(this._store);

  final ConfigStore _store;

  @override
  Future<CastAddress?> read() => _store.readCachedAddress();

  @override
  Future<void> write(CastAddress address) => _store.writeCachedAddress(address);

  @override
  Future<void> clear() => _store.clearCachedAddress();
}
