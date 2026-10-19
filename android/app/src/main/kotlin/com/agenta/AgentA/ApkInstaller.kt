package com.agenta.AgentA

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hand-rolled PackageInstaller bridge (cycle-28 P4; see
 * docs/design/in-app-update-mechanics.md §3 and contracts/update-engine.yaml §4).
 *
 * Channel `com.agenta.agenta/apk_install`:
 *  - canInstall()                     → Boolean (PackageManager.canRequestPackageInstalls)
 *  - startInstall(apkPath, sizeBytes) → commits a PackageInstaller session;
 *      terminal results arrive as `onInstallStatus` events
 *  - openInstallPermissionSettings()  → Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES
 *      for this package
 *
 * Native → Dart events: `onInstallStatus` {status: "installed"} or
 * {status: "failed", reason: <contract §4 reason>, detail: <status message>}.
 * STATUS_PENDING_USER_ACTION launches the single system confirmation here and
 * is NOT forwarded (contract §4 `channel_events`).
 */
class ApkInstaller(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.agenta.agenta/apk_install"
        const val ACTION_INSTALL_STATUS = "com.agenta.AgentA.INSTALL_STATUS"

        /** The live handler, for broadcast delivery from [ApkInstallReceiver]. */
        @Volatile
        var active: ApkInstaller? = null

        fun dispatchStatus(context: Context, intent: Intent) {
            active?.handleStatus(context, intent)
        }
    }

    /** Binds this instance as the method-call handler + status dispatcher. */
    fun attach() {
        channel.setMethodCallHandler(this)
        active = this
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(canInstall())
            "startInstall" -> startInstall(call, result)
            "openInstallPermissionSettings" -> {
                openInstallPermissionSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun canInstall(): Boolean =
        context.packageManager.canRequestPackageInstalls()

    private fun startInstall(call: MethodCall, result: MethodChannel.Result) {
        val apkPath = call.argument<String>("apkPath")
        val sizeBytes = call.argument<Number>("sizeBytes")?.toLong()
        if (apkPath.isNullOrEmpty()) {
            result.error("invalidFile", "apkPath is missing", null)
            return
        }
        val apk = File(apkPath)
        if (!apk.isFile || apk.length() <= 0L) {
            result.error("invalidFile", "APK file not found: $apkPath", null)
            return
        }
        if (!canInstall()) {
            result.error(
                "permissionDenied",
                "Installing from this app is not allowed (install unknown apps grant missing).",
                null,
            )
            return
        }
        val installer = context.packageManager.packageInstaller
        var sessionId = -1
        try {
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            params.setSize(sizeBytes?.takeIf { it > 0 } ?: apk.length())
            sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            try {
                session.openWrite("AgentA-update.apk", 0, apk.length()).use { out ->
                    apk.inputStream().use { input -> input.copyTo(out) }
                    session.fsync(out)
                }
                // Hardening (P1b §6, adopted by P7 H2): the staged file must
                // parse as an APK whose package is this app (applicationId
                // com.agenta.AgentA) — a foreign or corrupt archive never
                // reaches the system installer. No partial installs (§4).
                @Suppress("DEPRECATION")
                val archive = context.packageManager.getPackageArchiveInfo(apkPath, 0)
                if (archive == null || archive.packageName != context.packageName) {
                    installer.abandonSession(sessionId)
                    result.error(
                        "invalidFile",
                        "Staged file is not a valid AgentA APK (packageName=${archive?.packageName ?: "unparseable"}).",
                        null,
                    )
                    return
                }
                session.commit(statusIntentSender(sessionId))
            } finally {
                session.close()
            }
            result.success(null)
        } catch (e: Exception) {
            // Contract §4: no partial installs — abandon on every failure.
            // (PackageInstaller.abandonSession(int), the class-level API.)
            if (sessionId >= 0) {
                runCatching { installer.abandonSession(sessionId) }
            }
            result.error("sessionFailed", e.message, null)
        }
    }

    private fun statusIntentSender(sessionId: Int): IntentSender {
        val statusIntent = Intent(context, ApkInstallReceiver::class.java)
            .setAction(ACTION_INSTALL_STATUS)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The system fills EXTRA_STATUS/EXTRA_STATUS_MESSAGE into this
            // intent — it must stay mutable (required on Android 12+).
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent
            .getBroadcast(context, sessionId, statusIntent, flags)
            .intentSender
    }

    private fun openInstallPermissionSettings() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** Maps a PackageInstaller status callback onto the contract §4 mapping. */
    internal fun handleStatus(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Launch the single system confirmation and continue; the
                // pending state itself is not forwarded (contract §4).
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
                }
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                confirm?.let { runCatching { context.startActivity(it) } }
            }
            PackageInstaller.STATUS_SUCCESS ->
                emit(mapOf("status" to "installed"))
            else -> {
                val payload = mutableMapOf<String, Any?>(
                    "status" to "failed",
                    "reason" to reasonFor(status),
                )
                intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?.let { payload["detail"] = it }
                emit(payload)
            }
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        channel.invokeMethod("onInstallStatus", payload)
    }

    private fun reasonFor(status: Int): String = when (status) {
        PackageInstaller.STATUS_FAILURE_ABORTED -> "userCancelled"
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "permissionDenied"
        PackageInstaller.STATUS_FAILURE_CONFLICT -> "signatureMismatch"
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "invalidPackage"
        PackageInstaller.STATUS_FAILURE_INVALID -> "invalidPackage"
        PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
        PackageInstaller.STATUS_FAILURE_TIMEOUT -> "timeout"
        else -> "unknown"
    }
}
