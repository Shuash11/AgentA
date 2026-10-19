import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'install_failure_reason.dart';

/// Events emitted by [ApkInstallService.events] (contract §4 `install.result`).
sealed class InstallEvent {
  const InstallEvent();
}

/// The session is committed; the system confirmation governs from here
/// (no app-side cancel past this point).
final class InstallStarted extends InstallEvent {
  const InstallStarted();
}

/// STATUS_SUCCESS — the package was installed (in place, data preserved for a
/// same-certificate update).
final class InstallCompleted extends InstallEvent {
  const InstallCompleted();
}

/// Terminal failure; [detail] is the native status message (debug only).
final class InstallFailed extends InstallEvent {
  final InstallFailureReason reason;
  final String? detail;

  const InstallFailed(this.reason, {this.detail});
}

/// Hand-rolled bridge to the Android PackageInstaller session
/// (Kotlin `ApkInstaller`, channel `com.agenta.agenta/apk_install`) — zero
/// third-party packages on the install path (P1b ruling).
///
/// Contract: `contracts/update-engine.yaml` §4 (`install_flow.install`).
///  - [canInstall] → `PackageManager.canRequestPackageInstalls()` — the
///    per-app "install unknown apps" user grant;
///  - [startInstall] commits a session; terminal results arrive on [events];
///  - [openInstallPermissionSettings] routes the grant page for this package.
///
/// Failures are classified, never thrown (contract §4 `reason_mapping`).
class ApkInstallService {
  /// [channel] is injectable for hermetic tests (mock method-call handler).
  ApkInstallService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.agenta.agenta/apk_install',
  );

  final MethodChannel _channel;
  final StreamController<InstallEvent> _events =
      StreamController<InstallEvent>.broadcast();

  /// [InstallStarted] + terminal install events — contract §4.
  Stream<InstallEvent> get events => _events.stream;

  /// Whether the app may currently request package installs. False on any
  /// platform error (including non-Android platforms — the update flow is
  /// Android-only for now).
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException catch (e) {
      _log('[ApkInstall] canInstall failed: ${e.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Commits a PackageInstaller session for [apkPath]. Never throws: on
  /// success an [InstallStarted] event is emitted; on failure an
  /// [InstallFailed] event replaces it.
  Future<void> startInstall({required String apkPath, int? sizeBytes}) async {
    try {
      await _channel.invokeMethod<void>('startInstall', {
        'apkPath': apkPath,
        'sizeBytes': ?sizeBytes,
      });
      _events.add(const InstallStarted());
    } on PlatformException catch (e) {
      _events.add(
        InstallFailed(_reasonForPlatformCode(e.code), detail: e.message),
      );
    } on MissingPluginException {
      _events.add(
        const InstallFailed(
          InstallFailureReason.unknown,
          detail: 'install channel unavailable',
        ),
      );
    }
  }

  /// Routes to the per-app "install unknown apps" settings page
  /// (`Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`). Best-effort.
  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } catch (e) {
      _log('[ApkInstall] openInstallPermissionSettings failed: $e');
    }
  }

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'onInstallStatus') return null;
    final args = call.arguments;
    final map = args is Map
        ? args.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final status = map['status'];
    if (status == 'installed') {
      _events.add(const InstallCompleted());
    } else if (status == 'failed') {
      final reason = InstallFailureReason.fromChannelName(
        map['reason'] as String?,
      );
      _events.add(InstallFailed(reason, detail: map['detail'] as String?));
    } else {
      _log('[ApkInstall] unknown native status "$status" — ignored');
    }
    return null;
  }

  static InstallFailureReason _reasonForPlatformCode(String code) {
    switch (code) {
      case 'permissionDenied':
        return InstallFailureReason.permissionDenied;
      case 'invalidFile':
        return InstallFailureReason.invalidPackage;
      case 'sessionFailed':
      case 'unexpected':
      default:
        return InstallFailureReason.unknown;
    }
  }

  /// Test hygiene — closes the event stream and detaches the channel handler.
  @visibleForTesting
  void dispose() {
    unawaited(_events.close());
    _channel.setMethodCallHandler(null);
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
