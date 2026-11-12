package com.example.car_logix

import android.content.Context
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.car_logix/audio_control"
    private var beepSuppressed = false
    private var savedNotificationMuted = false
    private var savedSystemMuted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "suppressBeep") {
                    val suppress = call.argument<Boolean>("suppress") ?: false
                    setBeepSuppressed(suppress)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun setBeepSuppressed(suppress: Boolean) {
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (suppress && !beepSuppressed) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    savedNotificationMuted = am.isStreamMute(AudioManager.STREAM_NOTIFICATION)
                    savedSystemMuted = am.isStreamMute(AudioManager.STREAM_SYSTEM)
                    if (!savedNotificationMuted) {
                        am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_MUTE, 0)
                    }
                    if (!savedSystemMuted) {
                        am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_MUTE, 0)
                    }
                }
                beepSuppressed = true
            } else if (!suppress && beepSuppressed) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (!savedNotificationMuted) {
                        am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0)
                    }
                    if (!savedSystemMuted) {
                        am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_UNMUTE, 0)
                    }
                }
                beepSuppressed = false
            }
        } catch (_: SecurityException) {
            // Device is in strict Do-Not-Disturb policy mode; skip muting safely.
        } catch (_: Throwable) {
            // Guard OEM AudioManager quirks safely.
        }
    }

    override fun onDestroy() {
        setBeepSuppressed(false)
        super.onDestroy()
    }
}
