/// The Android multicast lock, over a method channel.
///
/// Without it mDNS silently returns nothing on Android — no error, no warning.
/// Held only for the duration of a browse, never for the app's lifetime,
/// because it costs battery.
library;

import 'package:flutter/services.dart';

import 'multicast_lock.dart';

class PlatformMulticastLock implements MulticastLock {
  const PlatformMulticastLock();

  static const MethodChannel _channel =
      MethodChannel('com.office.streamplayer/multicast');

  @override
  Future<void> acquire() => _invoke('acquire');

  @override
  Future<void> release() => _invoke('release');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Not Android: there is no lock to take.
    } on PlatformException {
      // Best effort. Discovery may still work, and failing here would be a
      // worse outcome than trying without the lock.
    }
  }
}
