package com.office.streamplayer.atemo_stream_player_viewer

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Holds a Wi-Fi multicast lock while mDNS discovery runs.
 *
 * Android drops multicast packets to save battery unless a lock is held, and
 * it does so silently: without this, discovery returns an empty result with no
 * error to explain why. The lock is acquired per browse and released after,
 * never held for the app's lifetime.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.office.streamplayer/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireLock()
                        result.success(null)
                    }
                    "release" -> {
                        releaseLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("streamplayer-discovery").apply {
            setReferenceCounted(true)
            acquire()
        }
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        // Releasing here too: a lock leaked across a config change would cost
        // battery for as long as the app lived.
        releaseLock()
        super.onDestroy()
    }
}
