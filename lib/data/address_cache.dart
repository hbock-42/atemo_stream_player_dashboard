/// Storage for the last address the device actually answered on.
///
/// An interface rather than a concrete store because the implementation needs
/// Flutter (`shared_preferences`), while everything that *uses* it — `data/`,
/// and therefore the relay — must stay pure Dart. The Flutter-backed
/// implementation lives in `config/`.
library;

import '../cast/cast_address.dart';

abstract interface class AddressCache {
  Future<CastAddress?> read();
  Future<void> write(CastAddress address);
  Future<void> clear();
}

/// The default for callers that do not want persistence (the relay, tests).
class NoAddressCache implements AddressCache {
  const NoAddressCache();

  @override
  Future<CastAddress?> read() async => null;

  @override
  Future<void> write(CastAddress address) async {}

  @override
  Future<void> clear() async {}
}
