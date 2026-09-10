/// How this instance of the app gets its data.
///
/// Web is always [SourceMode.relay] and needs no configuration at all: the
/// page was served by the relay, so it derives the socket URL from its own
/// origin. Native can use either.
library;

enum SourceMode { direct, relay }

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

  AppConfig copyWith({SourceMode? mode, String? manualHost, String? relayUrl}) => AppConfig(
        mode: mode ?? this.mode,
        manualHost: manualHost ?? this.manualHost,
        relayUrl: relayUrl ?? this.relayUrl,
      );
}
