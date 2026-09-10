/// Android requires a multicast lock to be held for mDNS to return anything.
///
/// Kept as an interface with a no-op default now that the app ships to browsers
/// only (ADR-0007): the relay runs discovery on a desktop or a Pi, where there
/// is no lock to take. If an Android build ever returns, the platform
/// implementation plugs in here rather than into `MdnsDiscovery`.
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
