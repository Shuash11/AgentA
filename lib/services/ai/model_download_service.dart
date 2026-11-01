import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../data/local/offline_model_dao.dart';
import 'offline_model_spec.dart';

enum ModelStatus { notInstalled, installing, ready, error }

/// Typed stall signal: the app-side watchdog fires this after
/// [ModelDownloadService.stallTimeoutForTest]'s production value elapses with
/// zero progress events. Brand-free; maps to a friendly retryable message in
/// [_friendlyDownloadError]. Raw plugin detail never reaches the UI.
class DownloadStalledException implements Exception {
  const DownloadStalledException([this.message = 'download stalled']);

  final String message;

  @override
  String toString() => 'DownloadStalledException: $message';
}

class ModelDownloadService extends ChangeNotifier {
  final OfflineModelDao _dao = OfflineModelDao();
  ModelStatus _status = ModelStatus.notInstalled;
  double _progress = 0.0;
  String? _errorMessage;
  DateTime? _lastProgressTime;
  bool _isSlowConnection = false;
  double _lastProgressValue = 0.0;
  double _lastNotifiedProgress = -1.0;
  static const double _notifyThreshold = 1.0;

  /// Permission-request ceiling. Mirrors the plugin's own 10s guard around
  /// its identical native request (smart_downloader): the host callback can
  /// never arrive, which would hang the await forever ahead of install().
  /// On timeout we treat the grant as denied and proceed — denial never
  /// blocks the download, it only hides the foreground notification.
  static const Duration _permissionTimeout = Duration(seconds: 10);

  /// Belt-and-braces ceiling for the whole install future. 60 minutes: the
  /// Gemma 4 E2B bundle is 2,588,147,712 B (~2.59 GB) and a ~1.5 MB/s
  /// transfer needs ~29 min — the old 30-min ceiling expired before a
  /// legitimate slow download could finish.
  static const Duration _installTimeout = Duration(minutes: 60);

  /// Stall watchdog window: 3 minutes with zero progress events. Generous
  /// vs the 60s slow-connection heuristic above (a merely slow transfer
  /// still emits events and keeps resetting this timer).
  static const Duration _stallTimeout = Duration(minutes: 3);

  /// Token for the in-flight install chain. Cancelling it asks the plugin
  /// to stop the native task (FileDownloader().cancelTaskWithId), so the
  /// download never outlives the app giving up on it.
  CancelToken? _activeCancelToken;

  /// App-side stall watchdog, armed while installing and reset on every
  /// progress event. Null when no install is in flight.
  Timer? _stallWatchdog;

  /// Set when the watchdog fires. Guards the install future's follow-on
  /// cancellation error from overwriting the surfaced stall state.
  bool _stallFired = false;

  ModelStatus get status => _status;
  double get progress => _progress;
  bool get isReady => _status == ModelStatus.ready;
  bool get isSlowConnection => _isSlowConnection;

  /// Filename of the superseded Gemma 3 1B asset — the uninstall id the
  /// v3 migration uses.
  static const String _legacyModelFileName = 'gemma3-1b-it-int4.task';

  /// Filename of the Gemma 4 E2B asset — the uninstall id the v4 migration
  /// uses. E2B left model selection (plan §4.9), so every device that still
  /// holds the asset holds a STRANDED one.
  ///
  /// Exact case matters: the pinned core keys a model by its persisted
  /// filename, and that filename is the install URL's last path segment
  /// (`path.basename(Uri.parse(url).path)` — network_source_handler.dart),
  /// so the E2B asset is persisted as `gemma-4-E2B-it.litertlm`. A
  /// case-mismatched probe would silently never migrate.
  static const String _e2bModelFileName = 'gemma-4-E2B-it.litertlm';

  /// Channel to the host MainActivity for the Android 13+ runtime
  /// POST_NOTIFICATIONS request (no permission_handler dependency).
  /// Best-effort only: denial merely hides the foreground download progress
  /// notification, the download itself still runs.
  static const MethodChannel _notificationsChannel = MethodChannel(
    'com.agenta.agenta/notifications',
  );

  /// The effective download URL for [spec] (env override wins WITHIN the
  /// selected class).
  ///
  /// The override substitutes the URL while the class keeps its own
  /// modelType/fileType — a CROSS-FORMAT override (a `.litertlm` URL forced
  /// onto the Qwen `.task` class) still fails at engine claim: the
  /// debug/enterprise escape hatch, accepted and recorded (contract §7
  /// override_caveat_amended).
  ///
  /// Shared by the install path and [ensureModelActive] so the plugin's
  /// idempotency key (derived from the URL filename) always matches.
  static String resolvedModelUrlFor(OfflineModelSpec spec) =>
      AppConfig.gemmaModelUrl.isNotEmpty ? AppConfig.gemmaModelUrl : spec.url;

  void _notifyStateChanged(ModelStatus oldStatus, double oldProgress) {
    if (oldStatus != _status || oldProgress != _progress) {
      notifyListeners();
    }
  }

  void _notifyProgress() {
    if ((_progress - _lastNotifiedProgress).abs() >= _notifyThreshold ||
        (_progress >= 100.0 && _lastNotifiedProgress < 100.0) ||
        _lastNotifiedProgress < 0) {
      _lastNotifiedProgress = _progress;
      notifyListeners();
    }
  }

  void _onDownloadProgress(int progress) {
    _progress = progress.toDouble();

    // Slow-connection heuristic: 60s without a progress increase.
    final now = DateTime.now();
    if (_progress > _lastProgressValue) {
      _lastProgressTime = now;
      _lastProgressValue = _progress;
      _isSlowConnection = false;
    } else if (_lastProgressTime != null) {
      final secondsSinceLastUpdate = now
          .difference(_lastProgressTime!)
          .inSeconds;
      if (secondsSinceLastUpdate > 60 && !_isSlowConnection) {
        _isSlowConnection = true;
        notifyListeners();
      }
    }
    // Any event — even one without an increase — proves the native task
    // is alive, so the stall watchdog restarts from here.
    if (_status == ModelStatus.installing) _armStallWatchdog();
    _notifyProgress();
  }

  /// (Re)arms the stall watchdog for [_stallTimeout] from now. Previous
  /// timer, if any, is cancelled first — at most one is ever pending.
  void _armStallWatchdog() {
    _cancelStallWatchdog();
    _stallWatchdog = Timer(
      stallTimeoutOverrideForTest ?? _stallTimeout,
      _onStallTimeout,
    );
  }

  /// Cancels the stall watchdog without touching anything else. Safe to
  /// call when no timer is pending.
  void _cancelStallWatchdog() {
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
  }

  /// Watchdog handler: no progress event arrived within the window, so the
  /// native task is presumed silently dead. Cancels it via the token and
  /// surfaces a typed, retryable stall error. Stale fires (state already
  /// left installing) are ignored.
  void _onStallTimeout() {
    _stallWatchdog = null;
    if (_status != ModelStatus.installing) return;
    _stallFired = true;
    _activeCancelToken?.cancel('Download stalled');
    _applyDownloadFailure(
      const DownloadStalledException(),
      logTag: 'stallWatchdog',
    );
    notifyListeners();
  }

  Future<void> checkModelExists() async {
    if (_status == ModelStatus.installing) return;

    final oldStatus = _status;
    final oldProgress = _progress;

    // Runs BEFORE the readiness read below: the migration resets the DB row
    // so the gate re-downloads the current asset instead of serving the
    // superseded one.
    await _migrateLegacyAssetIfPresent();
    await _migrateStrandedE2bAssetIfPresent();

    try {
      final sqliteReady = await _dao.isModelReady();

      if (!sqliteReady) {
        _status = ModelStatus.notInstalled;
        _progress = 0.0;
      } else {
        final modelStatus = await _dao.getModelStatus();
        final storedPath = modelStatus?['file_path'] as String?;

        if (storedPath != null && storedPath.isNotEmpty) {
          final file = File(storedPath);
          if (await file.exists()) {
            _status = ModelStatus.ready;
            _progress = 100.0;
          } else {
            await _dao.setModelNotInstalled();
            _status = ModelStatus.notInstalled;
            _progress = 0.0;
          }
        } else {
          // No path recorded — the plugin owns the model storage (app-private,
          // cleared together with our DB). Trust the DB flag: it is only
          // written after a completed install. Never gate on
          // FlutterEdgeAi.hasActiveModel() here — that spec is in-memory only
          // (null after every restart), so requiring it would downgrade a
          // fully downloaded model and keep the download gate closed forever.
          // If the plugin's copy were truly lost, ensureModelActive() at load
          // time re-downloads it transparently.
          _status = ModelStatus.ready;
          _progress = 100.0;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ModelDownload] checkModelExists failed: $e');
      _status = ModelStatus.notInstalled;
      _progress = 0.0;
    }
    _notifyStateChanged(oldStatus, oldProgress);
  }

  /// One-time migration (generation 2): the broken third-party mirror and
  /// official file share the filename `gemma3-1b-it-int4.task`, so install()
  /// skips the official copy unless the old file is removed. Marker set
  /// BEFORE uninstall so a crash never loops the download.
  static Future<void> _migrateStaleAssetIfPresent() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('model_asset_v2') == true) return;
    final dao = OfflineModelDao();
    final hasActive = FlutterEdgeAi.hasActiveModel();
    final daoReady = await dao.isModelReady();
    if (!hasActive && !daoReady) return;
    await prefs.setBool('model_asset_v2', true);
    await _uninstallLegacyModel();
    await dao.setModelNotInstalled();
  }

  /// One-time migration (generation 3): the Gemma 4 E2B bundle has a
  /// different filename, so install() adds it cleanly while the superseded
  /// 1B file (0.5 GB) lingers on disk. Uninstall that asset and reset the
  /// DB row so the download gate re-downloads the E2B bundle — no
  /// user-facing migration UI. Marker set BEFORE uninstall so a crash never
  /// loops the download.
  ///
  /// The trigger is the legacy asset itself (installed in the plugin's
  /// storage, or the active model), NOT "any model is present": the E2B
  /// bundle must never be uninstalled-and-reset by its own migration, which
  /// would strand the user behind a 2.59 GB re-download gate.
  static Future<void> _migrateLegacyAssetIfPresent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('model_asset_v3') == true) return;
      if (!await _legacyAssetPresent()) return;
      await prefs.setBool('model_asset_v3', true);
      await _uninstallLegacyModel();
      await OfflineModelDao().setModelNotInstalled();
    } catch (e) {
      // A migration must never break the download gate. The marker is set
      // BEFORE the uninstall (a crash mid-migration never loops the
      // download), so a failed uninstall is not retried on the next launch.
      if (kDebugMode) {
        debugPrint('[ModelDownload] legacy asset migration failed: $e');
      }
    }
  }

  /// Whether the superseded 1B asset is still present: installed in the
  /// plugin's storage, or the active model on this run.
  static Future<bool> _legacyAssetPresent() async {
    final override = legacyAssetPresentOverrideForTest;
    if (override != null) return override();
    final active = FlutterEdgeAi.activeModelSpec?.name == _legacyModelFileName;
    if (active) return true;
    return FlutterEdgeAi.isModelInstalled(_legacyModelFileName);
  }

  /// Removes the superseded 1B asset. Tolerant: an already-unregistered or
  /// already-missing model/file is safe to continue.
  static Future<void> _uninstallLegacyModel() async {
    final override = uninstallOverrideForTest;
    if (override != null) {
      await override(_legacyModelFileName);
      return;
    }
    try {
      await FlutterEdgeAi.uninstallModel(_legacyModelFileName);
    } catch (_) {
      // Already unregistered / file missing — safe to continue.
    }
  }

  /// Overrides the legacy-asset presence probe (test-only). When set, the
  /// migration uses it instead of asking the plugin.
  @visibleForTesting
  static Future<bool> Function()? legacyAssetPresentOverrideForTest;

  /// Overrides the legacy-asset uninstall (test-only). When set, the
  /// migration calls it instead of the plugin.
  @visibleForTesting
  static Future<void> Function(String modelId)? uninstallOverrideForTest;

  /// One-time migration (generation 4): the stranded E2B bundle.
  ///
  /// E2B LEFT MODEL SELECTION (plan §4.9): no device is offered the asset
  /// any more — the LiteRT-LM engine fails to load it on real arm64
  /// devices too (the lived evidence), and the MediaPipe `.task` engine is
  /// the multi-ABI engine. So EVERY device holding the E2B asset holds a
  /// STRANDED one: wasted 2.59 GB and a dead asset. Uninstall it and reset
  /// the DB row so the gate re-offers the selected spec (the Qwen `.task`
  /// flow on a device that clears the RAM floor, the honest message on the
  /// message-only class).
  ///
  /// The trigger is the STRANDED ASSET ITSELF — NEVER a generic "any model
  /// is present" condition (the v3 self-reset lesson of cycle-38 §4.8, in
  /// its GENERALIZED form): a Qwen-asset user must never fire v4, because
  /// both probe legs are false for them. The capability-verdict clause of
  /// the first cut is DELETED: no device is eligible for E2B any more, so
  /// the verdict is universal and the asset's presence is the whole
  /// trigger. Marker set BEFORE the uninstall so a crash never loops the
  /// download.
  static Future<void> _migrateStrandedE2bAssetIfPresent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('model_asset_v4') == true) return;
      if (!await _e2bAssetPresent()) return;
      await prefs.setBool('model_asset_v4', true);
      await _uninstallE2bAsset();
      await _resetDaoRowAfterE2bRemoval();
    } catch (e) {
      // A migration must never break the download gate. The marker is set
      // BEFORE the uninstall (a crash mid-migration never loops the
      // download), so a failed uninstall is not retried on the next launch.
      if (kDebugMode) {
        debugPrint('[ModelDownload] stranded E2B migration failed: $e');
      }
    }
  }

  /// The DAO row after the stranded E2B asset is gone.
  ///
  /// The row is reset to the SELECTED spec's identity — universally
  /// `qwen2.5-1.5b-it` (contract §2 identity_sites) — so the gate
  /// re-offers the selected asset.
  ///
  /// A row that already records the SELECTED spec as INSTALLED is NOT
  /// reset: that row describes the Qwen asset, which is still on the
  /// device, and resetting it would force a redundant 1.6 GB re-download
  /// of an asset the device already has (the both-assets composition —
  /// contract §4: "the gate's readiness read FINDS QWEN: no Qwen
  /// re-download is forced"). The durable truth is the DAO row — the same
  /// one the gate's readiness read consults.
  static Future<void> _resetDaoRowAfterE2bRemoval() async {
    final dao = OfflineModelDao();
    final row = await dao.getModelStatus();
    final rowDescribesSelectedAsset =
        row != null &&
        row['model_type'] == OfflineModelSpecTable.appIdentity &&
        await dao.isModelInstalled();
    if (rowDescribesSelectedAsset) return;
    await dao.setModelNotInstalled();
  }

  /// Whether the stranded E2B asset is still present: installed in the
  /// plugin's storage, or the active model on this run.
  ///
  /// The probe keys on the asset's FILENAME — the pinned core keys a model
  /// by its persisted filename (`isModelInstalled` takes a filename, and
  /// `activeModelSpec.name` IS the persisted filename on restore).
  static Future<bool> _e2bAssetPresent() async {
    final override = e2bAssetPresentOverrideForTest;
    if (override != null) return override();
    final active = FlutterEdgeAi.activeModelSpec?.name == _e2bModelFileName;
    if (active) return true;
    return FlutterEdgeAi.isModelInstalled(_e2bModelFileName);
  }

  /// Removes the stranded E2B asset. Tolerant: an already-unregistered or
  /// already-missing model/file is safe to continue.
  static Future<void> _uninstallE2bAsset() async {
    final override = uninstallOverrideForTest;
    if (override != null) {
      await override(_e2bModelFileName);
      return;
    }
    try {
      await FlutterEdgeAi.uninstallModel(_e2bModelFileName);
    } catch (_) {
      // Already unregistered / file missing — safe to continue.
    }
  }

  /// Overrides the stranded-E2B presence probe (test-only). When set, the
  /// v4 migration uses it instead of asking the plugin.
  @visibleForTesting
  static Future<bool> Function()? e2bAssetPresentOverrideForTest;

  Future<void> installModel() async {
    if (_status == ModelStatus.installing || _status == ModelStatus.ready) {
      return;
    }
    await _migrateStaleAssetIfPresent();
    await checkModelExists();
    if (_status == ModelStatus.ready) return;

    // The asset this device installs: the selection table decides (the Qwen
    // `.task` bundle on the single selection class). The message-only class
    // has NO asset — the gate never offers a download there, so this is a
    // defensive no-op.
    final spec = await OfflineModelSpecTable.currentSpec();
    if (spec == null) {
      if (kDebugMode) {
        debugPrint('[ModelDownload] no model asset for this device class');
      }
      return;
    }

    _status = ModelStatus.installing;
    _progress = 0.0;
    _errorMessage = null;
    _lastProgressTime = null;
    _isSlowConnection = false;
    _lastProgressValue = 0.0;
    _lastNotifiedProgress = -1.0;
    _stallFired = false;
    final token = CancelToken();
    _activeCancelToken = token;
    notifyListeners();

    // Android 13+ shows the foreground-service progress notification only
    // with the runtime POST_NOTIFICATIONS grant. Best-effort: denial never
    // blocks the download, it only hides the notification.
    await _ensureNotificationPermission();

    _armStallWatchdog();
    try {
      // Foreground (AppConfig.foregroundDownload, default true) keeps the
      // ~2.6GB transfer alive when the app is backgrounded (WorkManager
      // alone is subject to background limits). FOREGROUND_DOWNLOAD=false
      // is the no-rebuild workaround when the foreground path fails.
      // Timeout stays as belt-and-braces.
      // install() is idempotent (skips the download when the file is already
      // in the plugin's storage) and resolves only AFTER finalization, when
      // the active spec is set. Completing early — at the 100% progress
      // event — raced the plugin's file move and left the gate stuck, so
      // readiness is marked strictly after this future resolves.
      // The CancelToken ties the native task's lifetime to ours: whenever
      // the app gives up (timeout, stall, any failure), the token is
      // cancelled so the native download stops instead of lingering.
      final installFuture = installOverrideForTest != null
          ? installOverrideForTest!(token)
          : FlutterEdgeAi.installModel(
                  modelType: spec.modelType,
                  fileType: spec.fileType,
                )
                .fromNetwork(
                  resolvedModelUrlFor(spec),
                  token: AppConfig.hfToken.trim(),
                  foreground: AppConfig.foregroundDownload,
                )
                .withProgress(_onDownloadProgress)
                .withCancelToken(token)
                .install();
      await installFuture.timeout(
        installTimeoutOverrideForTest ?? _installTimeout,
      );

      _cancelStallWatchdog();
      _activeCancelToken = null;
      _progress = 100.0;
      await _dao.setModelReady(modelType: spec.identity);
      _status = ModelStatus.ready;
    } catch (e) {
      _cancelStallWatchdog();
      _activeCancelToken = null;
      // Stop the native task whenever the app gives up. Redundant when the
      // watchdog already cancelled (cancel() is idempotent), and harmless
      // when the transfer already finished — the plugin simply has nothing
      // left to cancel.
      if (!token.isCancelled) token.cancel('App gave up on the download');
      if (_stallFired) {
        // The watchdog already surfaced the typed stall error above; the
        // install future's follow-on cancellation error must not overwrite
        // it back to a silent/neutral state.
      } else if (_progress >= 100.0) {
        // Tolerance: some devices close the connection right after the final
        // byte while the install future unwinds. If the transfer reached
        // 100%, the file is complete — settle briefly and mark ready
        // (load-time rehydration covers any residual plugin-side
        // finalization).
        await Future.delayed(const Duration(seconds: 2));
        await _dao.setModelReady(modelType: spec.identity);
        _status = ModelStatus.ready;
        if (kDebugMode) {
          debugPrint(
            '[ModelDownload] install failed at 100% — treated as complete: $e',
          );
        }
      } else {
        _applyDownloadFailure(e, logTag: 'installModel');
      }
    }

    notifyListeners();
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS runtime grant via the host
  /// MainActivity. Always resolves within [_permissionTimeout] (the host
  /// callback can never arrive, which used to hang this await forever ahead
  /// of install()); false (denied, timed out, non-Android, or channel
  /// unavailable e.g. in widget tests) never blocks the download.
  Future<bool> _ensureNotificationPermission() async {
    // Test seam first so VM unit tests (non-Android host) can drive the
    // timeout path; production always takes the platform/channel path below.
    final testRequest = permissionRequestOverrideForTest;
    final testTimeout = permissionTimeoutOverrideForTest;
    if (testRequest != null || testTimeout != null) {
      try {
        final request = testRequest ?? () async => true;
        final granted = await request().timeout(
          testTimeout ?? _permissionTimeout,
          onTimeout: () => false,
        );
        return granted ?? false;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[ModelDownload] notification permission request failed: $e',
          );
        }
        return false;
      }
    }
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _notificationsChannel
          .invokeMethod<bool>('requestNotificationPermission')
          .timeout(_permissionTimeout, onTimeout: () => false);
      return granted ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[ModelDownload] notification permission request failed: $e',
        );
      }
      return false;
    }
  }

  /// Maps a download/install failure to a friendly, brand-free UI state.
  /// flutter_edge_ai 1.x throws typed [DownloadException] (switch over its
  /// sealed [DownloadError]); anything else gets a generic friendly message.
  /// Raw exception detail goes to debugPrint only — never to the UI.
  /// Cancellation is silent/neutral: back to not-installed with no error.
  void _applyDownloadFailure(Object error, {required String logTag}) {
    final friendly = _friendlyDownloadError(error);
    if (friendly == null) {
      _status = ModelStatus.notInstalled;
      _errorMessage = null;
      _progress = 0.0;
    } else {
      _status = ModelStatus.error;
      _errorMessage = friendly;
      unawaited(_dao.setModelError(friendly));
    }
    if (kDebugMode) {
      final retryable = error is DownloadException && error.error.isRetryable;
      debugPrint(
        '[ModelDownload] $logTag failed '
        '(typed=${error is DownloadException}, retryable=$retryable): $error',
      );
    }
  }

  /// Returns the user-facing message for [error], or null when the failure
  /// should stay silent (user cancellation).
  String? _friendlyDownloadError(Object error) {
    // Raw plugin cancellation (thrown by CancelToken.throwIfCancelled before
    // the task starts) stays silent exactly like the mapped CanceledError.
    if (CancelToken.isCancel(error)) return null;
    if (error is DownloadStalledException) {
      return 'Download stalled. Please try again.';
    }
    if (error is DownloadException) {
      return switch (error.error) {
        NotFoundError() =>
          'The offline model file could not be found at its source. Check the download link.',
        UnauthorizedError() || ForbiddenError() =>
          'Download authorization required. The model source is gated — please confirm your HF token is valid and the model license has been accepted. Never share the token.',
        RateLimitedError() => 'Too many download attempts. Try again later.',
        NetworkError() =>
          'No internet connection. Download will resume when you are back online.',
        CanceledError() => null,
        ServerError() || UnknownError() => 'Download failed. Please try again.',
      };
    }
    if (error is TimeoutException) {
      return 'Download timed out. Please try again.';
    }
    return 'Download failed. Please try again.';
  }

  @override
  void dispose() {
    _cancelStallWatchdog();
    super.dispose();
  }

  // Test hooks: thin delegates/overrides over the privates above.
  // Annotated — not public API. Production logic lives in the privates.
  @visibleForTesting
  String? friendlyDownloadErrorForTest(Object error) =>
      _friendlyDownloadError(error);

  @visibleForTesting
  void applyDownloadFailureForTest(Object error, String logTag) =>
      _applyDownloadFailure(error, logTag: logTag);

  /// Production timeout ceilings, exposed read-only for tests.
  @visibleForTesting
  static Duration get permissionTimeoutForTest => _permissionTimeout;

  @visibleForTesting
  static Duration get stallTimeoutForTest => _stallTimeout;

  @visibleForTesting
  static Duration get installTimeoutForTest => _installTimeout;

  /// Overrides the platform permission request (test-only). When set,
  /// [_ensureNotificationPermission] uses it instead of the host channel,
  /// even on non-Android VM hosts.
  @visibleForTesting
  Future<bool?> Function()? permissionRequestOverrideForTest;

  /// Overrides the permission-request ceiling (test-only).
  @visibleForTesting
  Duration? permissionTimeoutOverrideForTest;

  /// Overrides the stall-watchdog window (test-only).
  @visibleForTesting
  Duration? stallTimeoutOverrideForTest;

  /// Overrides the whole-install ceiling (test-only).
  @visibleForTesting
  Duration? installTimeoutOverrideForTest;

  /// Overrides the plugin install chain (test-only). Receives the same
  /// [CancelToken] production passes to `.withCancelToken`, so tests can
  /// observe cancellation without touching the native plugin.
  @visibleForTesting
  Future<void> Function(CancelToken token)? installOverrideForTest;

  @visibleForTesting
  Future<bool> ensureNotificationPermissionForTest() =>
      _ensureNotificationPermission();

  /// Fires the watchdog handler immediately, without waiting out the
  /// window. Only takes effect while installing (matches the timer path).
  @visibleForTesting
  void fireStallTimeoutForTest() => _onStallTimeout();

  @visibleForTesting
  bool get hasActiveWatchdogForTest => _stallWatchdog?.isActive ?? false;

  @visibleForTesting
  bool get stallFiredForTest => _stallFired;

  /// Re-establishes the plugin's active-model spec for this process.
  /// On flutter_edge_ai 1.11.4, initialize() already auto-restores the
  /// previously-active model identity from SharedPreferences, so
  /// hasActiveModel() is usually true at startup and this returns early.
  /// The install() below is the defensive remainder: it is idempotent
  /// (skips the download when the file is already in the plugin's storage)
  /// and transparently re-downloads — foreground per
  /// [AppConfig.foregroundDownload] — when the storage was lost or prefs
  /// restore failed.
  static Future<bool> ensureModelActive() async {
    await _migrateStaleAssetIfPresent();
    await _migrateLegacyAssetIfPresent();
    await _migrateStrandedE2bAssetIfPresent();
    if (FlutterEdgeAi.hasActiveModel()) return true;
    // The asset this device runs — the selection table decides. The
    // message-only class has none: nothing can be rehydrated there.
    final spec = await OfflineModelSpecTable.currentSpec();
    if (spec == null) return false;
    try {
      await FlutterEdgeAi.installModel(
            modelType: spec.modelType,
            fileType: spec.fileType,
          )
          .fromNetwork(
            resolvedModelUrlFor(spec),
            token: AppConfig.hfToken.trim(),
            foreground: AppConfig.foregroundDownload,
          )
          .install()
          .timeout(const Duration(minutes: 60));
      return FlutterEdgeAi.hasActiveModel();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ModelDownload] ensureModelActive failed: $e');
      }
      return false;
    }
  }

  String? get errorMessage => _errorMessage;
}
