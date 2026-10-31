package com.agenta.AgentA

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun getRenderMode(): RenderMode = RenderMode.texture

    private val notificationsChannel = "com.agenta.agenta/notifications"
    private val notificationPermissionCode = 9001
    private var pendingNotificationResult: MethodChannel.Result? = null

    // Cycle-40 P1: the device-ABI probe. The LiteRT-LM engine ships its
    // native stack for android_arm64 only, so the app asks the platform
    // which ABIs it supports before it offers the 2.59 GB model download.
    private val deviceChannel = "com.agenta.agenta/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationsChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "requestNotificationPermission") {
                requestNotificationPermission(result)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "supportedAbis") {
                result.success(Build.SUPPORTED_ABIS.toList())
            } else {
                result.notImplemented()
            }
        }
        // Cycle-28 in-app update: hand-rolled PackageInstaller bridge
        // (docs/design/in-app-update-mechanics.md §3).
        ApkInstaller(
            applicationContext,
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                ApkInstaller.CHANNEL_NAME,
            ),
        ).attach()
    }

    // Android 13+ requires a runtime POST_NOTIFICATIONS grant for the
    // foreground-download progress notification to show. Pre-13 always
    // succeeds. Denial is non-fatal: the download still runs, only the
    // notification stays hidden — so the result is a plain boolean and
    // never an error.
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingNotificationResult?.success(false)
        pendingNotificationResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        }
    }
}
