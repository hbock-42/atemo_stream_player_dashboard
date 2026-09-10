/// DISC-04: the cached address, the parallel browse, and the three-strikes rule.
library;

import 'dart:async';

import 'package:atemo_stream_player_viewer/cast/cast_address.dart';
import 'package:atemo_stream_player_viewer/data/address_cache.dart';
import 'package:atemo_stream_player_viewer/data/cached_address_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCache implements AddressCache {
  FakeCache([this.stored]);

  CastAddress? stored;
  int clears = 0;
  final List<CastAddress> writes = [];

  @override
  Future<CastAddress?> read() async => stored;

  @override
  Future<void> write(CastAddress address) async {
    stored = address;
    writes.add(address);
  }

  @override
  Future<void> clear() async {
    stored = null;
    clears++;
  }
}

void main() {
  const cached = CastAddress(host: '10.0.0.7', friendlyName: 'Office');
  const discovered = CastAddress(host: '10.0.0.9', friendlyName: 'Office');

  test('a cached address is returned without waiting for discovery', () async {
    final browse = Completer<CastAddress?>();
    final resolver = CachedAddressResolver(
      cache: FakeCache(cached),
      discover: () => browse.future,
    );

    // The whole point of DISC-04: mDNS has not answered and never will here,
    // yet resolve completes. Without the parallelism this test would hang.
    expect(await resolver.resolve(), cached);
    expect(browse.isCompleted, isFalse, reason: 'discovery ran in parallel, unawaited');
    browse.complete(null);
  });

  test('discovery starts before the cache is read, so a miss costs no extra time', () async {
    var started = false;
    final cache = FakeCache();
    final resolver = CachedAddressResolver(
      cache: cache,
      discover: () async {
        started = true;
        return discovered;
      },
    );

    expect(await resolver.resolve(), discovered);
    expect(started, isTrue);
    expect(cache.stored, discovered, reason: 'a fresh find is remembered for next launch');
  });

  test('the manual host beats both the cache and discovery', () async {
    final resolver = CachedAddressResolver(
      cache: FakeCache(cached),
      discover: () async => discovered,
      manualHost: '192.168.1.50',
    );

    expect((await resolver.resolve())!.host, '192.168.1.50');
  });

  test('an empty manual host is ignored rather than dialled', () async {
    final resolver = CachedAddressResolver(
      cache: FakeCache(cached),
      discover: () async => discovered,
      manualHost: '',
    );

    expect(await resolver.resolve(), cached);
  });

  test('forceRefresh drops the cache and re-browses', () async {
    final cache = FakeCache(cached);
    var browses = 0;
    final resolver = CachedAddressResolver(
      cache: cache,
      discover: () async {
        browses++;
        return discovered;
      },
    );

    expect(await resolver.resolve(), cached);
    // CastClient asks for this after three consecutive failures.
    expect(await resolver.resolve(forceRefresh: true), discovered);
    expect(cache.clears, 1);
    expect(cache.stored, discovered);
    expect(browses, 2, reason: 'the stale in-flight browse must not answer the refresh');
  });

  test('a failing browse resolves to null instead of escaping as an async error', () async {
    final resolver = CachedAddressResolver(
      cache: FakeCache(),
      discover: () async => throw StateError('multicast refused'),
    );

    expect(await resolver.resolve(), isNull);
  });

  test('markConnected remembers the address that actually worked', () async {
    final cache = FakeCache(cached);
    final resolver = CachedAddressResolver(cache: cache, discover: () async => null);

    await resolver.resolve();
    await resolver.markConnected();
    expect(cache.writes, [cached]);
  });

  test('markConnected before any resolve writes nothing', () async {
    final cache = FakeCache();
    final resolver = CachedAddressResolver(cache: cache, discover: () async => null);

    await resolver.markConnected();
    expect(cache.writes, isEmpty);
  });

  test('a failed resolve leaves nothing to remember', () async {
    final cache = FakeCache();
    final resolver = CachedAddressResolver(cache: cache, discover: () async => null);

    expect(await resolver.resolve(), isNull);
    await resolver.markConnected();
    expect(cache.writes, isEmpty);
  });
}
