/// Android requires a multicast lock to be held for mDNS to return anything.
///
/// The interface is here, in Flutter-free code, so `discovery/` can be used by
/// the relay running headless on a desktop or a Pi. The Flutter-backed
/// implementation lives in `platform_multicast_lock.dart` and is supplied by
/// the app.
library;

abstract interface class MulticastLock {
  Future<void> acquire();
  Future<void> release();
}

/// Everywhere except Android there is nothing to acquire.
class NoopMulticastLock implements MulticastLock {
  const NoopMulticastLock();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}
