package com.agenta.AgentA

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives the PackageInstaller session commit status for [ApkInstaller]
 * (explicit broadcast; the manifest declares it `android:exported="false"` —
 * the only sender is our own PendingIntent) and forwards it to the live
 * channel handler.
 */
class ApkInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ApkInstaller.dispatchStatus(context.applicationContext, intent)
    }
}
