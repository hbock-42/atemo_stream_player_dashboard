/// The app's live configuration: loaded once at startup, persisted on every
/// change, and broadcast so the source can be rebuilt in place (CORE-04).
///
/// It is both a `ChangeNotifier` (for a settings screen to rebuild against)
/// and a `Stream<AppConfig>` (for `data/ReconfigurableSource`, which must stay
/// Flutter-free because the relay lifts `data/` unchanged).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'config_store.dart';

class AppConfigController extends ChangeNotifier {
  AppConfigController({ConfigStore? store, AppConfig initial = const AppConfig()})
      : _store = store ?? ConfigStore(),
        _config = initial;

  final ConfigStore _store;
  final StreamController<AppConfig> _changes = StreamController<AppConfig>.broadcast();

  AppConfig _config;
  AppConfig get config => _config;

  /// Every configuration after the current one. Deliberately not replaying:
  /// the source is built from [config] and only needs to hear about changes.
  Stream<AppConfig> get changes => _changes.stream;

  /// Reads persisted values over the defaults. Await this before building the
  /// first source, so a restart resumes in the mode the user chose.
  Future<void> load() async {
    final loaded = await _store.load(fallback: _config);
    if (loaded == _config) return;
    _config = loaded;
    _publish();
  }

  Future<void> setMode(SourceMode mode) => _update(_config.copyWith(mode: mode));

  Future<void> setManualHost(String? host) => _update(
        _config.copyWith(manualHost: host, clearManualHost: host == null || host.trim().isEmpty),
      );

  Future<void> setRelayUrl(String? url) => _update(
        _config.copyWith(relayUrl: url, clearRelayUrl: url == null || url.trim().isEmpty),
      );

  Future<void> _update(AppConfig next) async {
    if (next == _config) return;
    _config = next;
    _publish();
    // Persist after publishing: the UI should not wait on the platform store
    // to show the change it just made.
    await _store.save(next);
  }

  void _publish() {
    notifyListeners();
    if (!_changes.isClosed) _changes.add(_config);
  }

  @override
  void dispose() {
    unawaited(_changes.close());
    super.dispose();
  }
}
