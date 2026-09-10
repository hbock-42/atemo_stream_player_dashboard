/// How this instance of the app gets its data.
///
/// Web is always [SourceMode.relay] and needs no configuration at all: the
/// page was served by the relay, so it derives the socket URL from its own
/// origin. Native can use either.
///
/// A plain value: no Flutter, no I/O. Persisting it is `config/config_store.dart`'s
/// job and reacting to changes is `config/app_config_controller.dart`'s, which
/// is what lets `data/` — and therefore the relay — depend on this file.
library;

enum SourceMode { direct, relay }

/// Parses a persisted mode name, tolerating anything we no longer recognise
/// rather than throwing at startup on a value an older build wrote.
SourceMode? sourceModeFromName(String? name) => switch (name) {
      'direct' => SourceMode.direct,
      'relay' => SourceMode.relay,
      _ => null,
    };

class AppConfig {
  const AppConfig({
    this.mode = SourceMode.direct,
    this.manualHost,
    this.relayUrl,
  });

  final SourceMode mode;

  /// Set to bypass discovery on a network where mDNS is blocked.
  final String? manualHost;

  /// Explicit relay URL. On web this is left null and derived from the origin.
  final String? relayUrl;

  /// Null and empty are the same thing for the two host fields — a text field
  /// the user cleared must mean "unset", not "connect to the empty string".
  AppConfig copyWith({
    SourceMode? mode,
    String? manualHost,
    String? relayUrl,
    bool clearManualHost = false,
    bool clearRelayUrl = false,
  }) =>
      AppConfig(
        mode: mode ?? this.mode,
        manualHost: clearManualHost ? null : _blankToNull(manualHost) ?? this.manualHost,
        relayUrl: clearRelayUrl ? null : _blankToNull(relayUrl) ?? this.relayUrl,
      );

  static String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value.trim();

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.mode == mode &&
      other.manualHost == manualHost &&
      other.relayUrl == relayUrl;

  @override
  int get hashCode => Object.hash(mode, manualHost, relayUrl);

  @override
  String toString() => 'AppConfig(${mode.name}, manualHost: $manualHost, relayUrl: $relayUrl)';
}
