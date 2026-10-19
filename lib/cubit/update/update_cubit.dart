import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/update/apk_download_service.dart';
import '../../services/update/apk_install_service.dart';
import '../../services/update/install_failure_reason.dart';
import '../../services/update/version_check_service.dart';
import '../../services/update/version_source.dart';

/// Update-flow status (Adviser contract; the install-flow states per
/// `contracts/update-engine.yaml` §4).
enum UpdateStatus {
  idle,
  checking,
  available,
  forced,
  downloading,
  readyToInstall,
  installing,
  installed,
  installFailed,
}

/// State of the update dialog feature.
class UpdateState {
  final UpdateStatus status;

  /// Running app version, e.g. "1.1.0" (from package_info_plus). Empty when unknown.
  final String currentVersion;

  /// Running app build number (from package_info_plus). 0 when unknown.
  final int currentBuild;

  final RemoteRelease? remote;

  /// Download progress 0..1 while [UpdateStatus.downloading] (1% steps).
  final double downloadProgress;

  /// Verified APK file path (set at [UpdateStatus.readyToInstall]; retained
  /// for [retry] until a new download replaces it).
  final String? apkPath;

  /// Failure reason while [UpdateStatus.installFailed] (contract §4).
  final InstallFailureReason? installFailureReason;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.currentVersion = '',
    this.currentBuild = 0,
    this.remote,
    this.downloadProgress = 0,
    this.apkPath,
    this.installFailureReason,
  });

  bool get isForced => status == UpdateStatus.forced;

  /// True while the user-initiated install flow owns the state — completed
  /// automatic check results must not clobber it (contract §4
  /// `transition_rules`).
  bool get isFlowActive =>
      status == UpdateStatus.downloading ||
      status == UpdateStatus.readyToInstall ||
      status == UpdateStatus.installing;

  /// Whether the dialog should be shown for this state (Adviser show rules,
  /// cycle-29 P1 — the 24-hour snooze):
  ///  - forced (min-version) updates ALWAYS show;
  ///  - available shows iff the snooze has expired, or a NEWER version
  ///    overrides it (the snoozed version differs from the offered one);
  ///  - no snooze → show.
  bool shouldShow({
    required int? snoozedUntilEpochMs,
    required String? snoozedVersion,
  }) {
    if (status == UpdateStatus.forced) return true;
    if (status != UpdateStatus.available) return false;
    final version = remote?.version;
    if (version == null) return true;
    // A newer version always overrides the snooze.
    if (snoozedVersion != null && snoozedVersion != version) return true;
    // Same version (or no version stored): show iff the snooze has expired.
    if (snoozedUntilEpochMs == null) return true;
    return DateTime.now().isAfter(
      DateTime.fromMillisecondsSinceEpoch(snoozedUntilEpochMs),
    );
  }

  UpdateState copyWith({
    UpdateStatus? status,
    String? currentVersion,
    int? currentBuild,
    RemoteRelease? remote,
    double? downloadProgress,
    String? apkPath,
    InstallFailureReason? installFailureReason,
    bool resetInstallFailure = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      currentBuild: currentBuild ?? this.currentBuild,
      remote: remote ?? this.remote,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      apkPath: apkPath ?? this.apkPath,
      installFailureReason: resetInstallFailure
          ? null
          : (installFailureReason ?? this.installFailureReason),
    );
  }

  @override
  String toString() =>
      'UpdateState(status: ${status.name}, current: $currentVersion+$currentBuild, remote: ${remote?.version})';
}

/// Drives the update dialog from [VersionCheckService].
///
/// Wires to [VersionCheckService.instance] (injectable for tests): subscribes
/// to `resultStream` (cancelled in [close]), maps service levels →
/// [UpdateStatus], and persists the 24-hour snooze via the
/// `SharedPreferencesAsync` API (cycle-29 P1).
///
/// Show rules (Adviser, cycle-29): forced (min-version) → always show, and
/// the snooze refuses it; available → show only after the 24-hour "Later"
/// snooze has expired — "Later" persists a snooze deadline + the snoozed
/// version, and a newer release always overrides the snooze immediately.
/// Results arriving before the persisted snooze loads are buffered and
/// applied once it does, so a snoozed version can never flash the dialog.
/// The legacy per-version dismissal key is cleared once on migration and
/// never read.
class UpdateCubit extends Cubit<UpdateState> {
  /// The 24-hour snooze (cycle-29 P1): persisted deadline (epoch ms) + the
  /// version it was snoozed for — a newer release overrides the snooze.
  static const String snoozedUntilEpochMsKey = 'update_snoozed_until_epoch_ms';
  static const String snoozedVersionKey = 'update_snoozed_version';
  static const Duration snoozeDuration = Duration(hours: 24);

  /// LEGACY (cycle-27): the per-version dismissal key — dead data since the
  /// snooze; cleared once on migration, never read into behavior.
  static const String dismissedVersionKey = 'update_dismissed_version';

  final VersionCheckService _service;
  final ApkDownloadService _downloadService;
  final ApkInstallService _installService;
  StreamSubscription<UpdateCheckResult>? _subscription;
  StreamSubscription<InstallEvent>? _installSubscription;
  int? _snoozedUntilEpochMs;
  String? _snoozedVersion;
  bool _snoozeLoaded = false;
  UpdateCheckResult? _pendingResult; // result seen before the snooze loaded
  UpdateStatus? _flowOrigin; // status before the install flow started

  UpdateCubit({
    VersionCheckService? service,
    ApkDownloadService? downloadService,
    ApkInstallService? installService,
  }) : _service = service ?? VersionCheckService.instance,
       _downloadService = downloadService ?? ApkDownloadService(),
       _installService = installService ?? ApkInstallService(),
       super(const UpdateState()) {
    _init();
  }

  /// The snooze deadline (epoch ms) — null when no snooze is set.
  int? get snoozedUntilEpochMs => _snoozedUntilEpochMs;

  /// The version the snooze was set for — null when no snooze is set.
  String? get snoozedVersion => _snoozedVersion;

  void _init() {
    _subscription = _service.resultStream.listen(_onResult);
    _installSubscription = _installService.events.listen(_onInstallEvent);
    // Seed from a result the service may already have emitted (e.g. the check
    // ran before this cubit was created).
    final last = _service.lastResult;
    if (last != null) _onResult(last);
    unawaited(_loadSnooze());
  }

  Future<void> _loadSnooze() async {
    try {
      // SharedPreferencesAsync (new API, not the legacy singleton). Its
      // constructor throws StateError when the platform is unset (unit tests),
      // so construction is covered by the same defensive guard.
      final prefs = SharedPreferencesAsync();
      // Migration (cycle-29 P1): the old per-version dismissal key is dead
      // data — cleared once when present, never read into behavior.
      final legacy = await prefs.getString(dismissedVersionKey);
      if (legacy != null) {
        await prefs.remove(dismissedVersionKey);
        _log('[UpdateCubit] legacy dismissal key cleared');
      }
      final until = await prefs.getInt(snoozedUntilEpochMsKey);
      final version = await prefs.getString(snoozedVersionKey);
      _snoozedUntilEpochMs = until;
      _snoozedVersion = (version == null || version.isEmpty) ? null : version;
    } catch (e) {
      // Defensive: unreadable prefs must never block the feature.
      _snoozedUntilEpochMs = null;
      _snoozedVersion = null;
      _log('[UpdateCubit] snooze load failed: $e');
    } finally {
      _snoozeLoaded = true;
      // Apply a result that arrived while the snooze was loading.
      final pending = _pendingResult;
      _pendingResult = null;
      if (pending != null) _applyResult(pending);
    }
  }

  void _onResult(UpdateCheckResult result) {
    if (!_snoozeLoaded) {
      _pendingResult = result;
      return;
    }
    _applyResult(result);
  }

  /// Maps a fresh service result → status per the Adviser show rules.
  /// While the install flow is active the state is owned by the flow — a
  /// completed automatic check must not clobber it (contract §4).
  void _applyResult(UpdateCheckResult result) {
    if (state.isFlowActive) {
      _log(
        '[UpdateCubit] result ignored — install flow active (${state.status.name})',
      );
      return;
    }
    switch (result.level) {
      case UpdateLevel.forced:
        emit(_fromResult(result, UpdateStatus.forced));
      case UpdateLevel.available:
        // The snooze is applied at [UpdateState.shouldShow] (cycle-29 P1):
        // the state carries `available`; the host consults the persisted
        // snooze (deadline + version) when deciding to show.
        emit(_fromResult(result, UpdateStatus.available));
      case UpdateLevel.none:
        emit(_fromResult(result, UpdateStatus.idle));
    }
  }

  /// Force a network check now (user-initiated — the service still enforces
  /// its backoff/debug gates). While the call runs the state is
  /// [UpdateStatus.checking]; a failed/skipped check returns to idle so the
  /// UI never gets stuck on "checking".
  Future<void> checkNow() async {
    emit(state.copyWith(status: UpdateStatus.checking));
    final outcome = await _service.checkNow();
    if (outcome is! UpdateCheckCompleted) {
      if (state.status == UpdateStatus.checking) {
        emit(state.copyWith(status: UpdateStatus.idle));
      }
    }
    // Completed: the resultStream listener has already mapped it (the service
    // adds the result before returning; applying again is idempotent).
  }

  /// Snoozes the update prompt for 24 hours (cycle-29 P1): persists
  /// now + 24h and the current remote version, and returns to idle. A newer
  /// release overrides the snooze immediately ([UpdateState.shouldShow]);
  /// forced updates are never snoozed, and the install flow's in-flight
  /// states must never be snoozed by a stray dialog close (contract §4).
  Future<void> snoozeFor24Hours() async {
    final remote = state.remote;
    if (state.isFlowActive ||
        state.status == UpdateStatus.forced ||
        remote == null) {
      return;
    }
    final version = remote.version;
    final untilEpochMs = DateTime.now()
        .add(snoozeDuration)
        .millisecondsSinceEpoch;
    try {
      await SharedPreferencesAsync().setInt(
        snoozedUntilEpochMsKey,
        untilEpochMs,
      );
      await SharedPreferencesAsync().setString(snoozedVersionKey, version);
      _snoozedUntilEpochMs = untilEpochMs;
      _snoozedVersion = version;
    } catch (e) {
      // Persist failure — still snooze in memory for this session.
      _snoozedUntilEpochMs = untilEpochMs;
      _snoozedVersion = version;
      _log('[UpdateCubit] snooze persist failed: $e');
    }
    emit(state.copyWith(status: UpdateStatus.idle));
  }

  /// Starts the user-initiated in-app update flow: download + verify, then
  /// [UpdateStatus.readyToInstall] (contract §4). Callable from
  /// available/forced — or from [UpdateStatus.installFailed] as a retry.
  Future<void> downloadUpdate() async {
    final remote = state.remote;
    if (remote == null || (remote.downloadUrl ?? '').isEmpty) return;
    final status = state.status;
    if (status != UpdateStatus.available &&
        status != UpdateStatus.forced &&
        status != UpdateStatus.installFailed) {
      return;
    }
    _flowOrigin = status == UpdateStatus.installFailed
        ? (state.isForced ? UpdateStatus.forced : UpdateStatus.available)
        : status;
    emit(
      state.copyWith(
        status: UpdateStatus.downloading,
        downloadProgress: 0,
        resetInstallFailure: true,
      ),
    );

    final result = await _downloadService.download(
      remote,
      onProgress: _onDownloadProgress,
    );
    if (isClosed) return;
    switch (result) {
      case ApkDownloaded(:final filePath):
        emit(
          state.copyWith(
            status: UpdateStatus.readyToInstall,
            apkPath: filePath,
            downloadProgress: 1,
          ),
        );
      case ApkDownloadCancelled():
        emit(state.copyWith(status: _flowOrigin ?? UpdateStatus.available));
      case ApkDownloadFailed(:final reason):
        emit(
          state.copyWith(
            status: UpdateStatus.installFailed,
            installFailureReason: reason,
          ),
        );
    }
  }

  /// Cancels the in-flight download; the state returns to the pre-download
  /// status (contract §4: app-side cancel exists only while downloading).
  void cancelDownload() {
    if (state.status != UpdateStatus.downloading) return;
    _downloadService.cancel();
  }

  /// Starts the install hand-off for the verified file. When the per-app
  /// permission is missing, the state becomes
  /// [InstallFailureReason.permissionDenied] and the UI routes
  /// [openInstallPermissionSettings] (contract §4 `reason_mapping`).
  Future<void> installUpdate() async {
    if (state.status != UpdateStatus.readyToInstall) return;
    final apkPath = state.apkPath;
    if (apkPath == null || apkPath.isEmpty) return;

    final canInstall = await _installService.canInstall();
    if (isClosed) return;
    if (!canInstall) {
      emit(
        state.copyWith(
          status: UpdateStatus.installFailed,
          installFailureReason: InstallFailureReason.permissionDenied,
        ),
      );
      return;
    }

    emit(state.copyWith(status: UpdateStatus.installing));
    await _installService.startInstall(
      apkPath: apkPath,
      sizeBytes: state.remote?.assetSizeBytes,
    );
    // Terminal outcomes arrive via [_onInstallEvent].
  }

  /// Retries after [UpdateStatus.installFailed]: installs again when the
  /// verified file is still on hand, otherwise re-downloads (contract §4).
  Future<void> retry() async {
    if (state.status != UpdateStatus.installFailed) return;
    if ((state.apkPath ?? '').isNotEmpty) {
      emit(state.copyWith(status: UpdateStatus.readyToInstall));
      await installUpdate();
    } else {
      await downloadUpdate();
    }
  }

  /// Routes to the per-app "install unknown apps" settings page.
  Future<void> openInstallPermissionSettings() =>
      _installService.openInstallPermissionSettings();

  /// Progress is quantized to 1% steps — no state churn per network chunk.
  void _onDownloadProgress(double progress) {
    if (isClosed || state.status != UpdateStatus.downloading) return;
    final stepped = (progress * 100).floor() / 100;
    if (stepped == state.downloadProgress) return;
    emit(state.copyWith(downloadProgress: stepped));
  }

  void _onInstallEvent(InstallEvent event) {
    if (isClosed) return;
    switch (event) {
      case InstallStarted():
        emit(state.copyWith(status: UpdateStatus.installing));
      case InstallCompleted():
        emit(state.copyWith(status: UpdateStatus.installed));
      case InstallFailed(:final reason):
        emit(
          state.copyWith(
            status: UpdateStatus.installFailed,
            installFailureReason: reason,
          ),
        );
    }
  }

  UpdateState _fromResult(UpdateCheckResult result, UpdateStatus status) {
    return UpdateState(
      status: status,
      currentVersion: result.currentVersion ?? state.currentVersion,
      currentBuild:
          int.tryParse(result.currentBuild ?? '') ?? state.currentBuild,
      remote: result.remote,
    );
  }

  @override
  Future<void> close() {
    unawaited(_subscription?.cancel());
    unawaited(_installSubscription?.cancel());
    return super.close();
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
