package id.my.informatikatsu.smartlms

import android.content.res.Configuration
import android.os.Build
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Kanal "smartlms/guard" (lihat lib/core/security/exam_guard.dart & lib/core/time/server_clock.dart):
 *  enable  → FLAG_SECURE, sembunyikan overlay aplikasi lain (API 31+), screen pinning; balas status split-screen
 *  disable → kembalikan semuanya
 *  elapsed → jam monotonic (ms sejak boot, termasuk deep sleep) — tidak terpengaruh jam HP
 * Event ke Dart: multiWindow(bool)
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartlms/guard").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) window.setHideOverlayWindows(true)
                        // Screen pinning: Android menampilkan konfirmasi; ditolak pun ujian tetap jalan (keluar aplikasi tetap tercatat).
                        runCatching { startLockTask() }
                        result.success(mapOf("multiWindow" to isInMultiWindowMode))
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) window.setHideOverlayWindows(false)
                        runCatching { stopLockTask() }
                        result.success(null)
                    }
                    "elapsed" -> result.success(SystemClock.elapsedRealtime())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        channel?.invokeMethod("multiWindow", isInMultiWindowMode)
    }
}
