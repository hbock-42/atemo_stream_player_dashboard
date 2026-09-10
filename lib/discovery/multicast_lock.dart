/// Android requires a multicast lock to be held for mDNS to return anything.
///
/// Without it discovery silently returns an empty result — no error, no
/// warning. The lock is held only for the duration of a browse, never for the
/// app's lifetime, because it costs battery.
library;

import 'package:flutter/services.dart';

class MulticastLock {
  static const MethodChannel _channel =
      MethodChannel('com.office.streamplayer/multicast');

  /// Runs [action] with the lock held, releasing it even if [action] throws.
  static Future<T> hold<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      await release();
    }
  }

  static Future<void> acquire() async {
    try {
      await _channel.invokeMethod<void>('acquire');
    } on MissingPluginException {
      // Not Android: nothing to acquire.
    } on PlatformException {
      // Best effort — discovery may still work, and failing here would be a
      // worse outcome than trying without the lock.
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on MissingPluginException {
      // Not Android.
    } on PlatformException {
      // Ignored, as above.
    }
  }
}
