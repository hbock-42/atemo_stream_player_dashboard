/// CASTV2 namespaces and the well-known endpoint ids.
library;

class CastNamespaces {
  const CastNamespaces._();

  static const connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const receiver = 'urn:x-cast:com.google.cast.receiver';
  static const media = 'urn:x-cast:com.google.cast.media';
}

class CastEndpoints {
  const CastEndpoints._();

  /// The receiver's fixed control endpoint. Device-level volume is addressed
  /// here, which is why it works with no app running.
  static const receiver = 'receiver-0';
}

/// The app id the device reports when nothing is playing. Treated as idle.
const String kBackdropAppId = 'E8C28D3C';

/// The display name the device reports when nothing is playing.
const String kBackdropDisplayName = 'Backdrop';
