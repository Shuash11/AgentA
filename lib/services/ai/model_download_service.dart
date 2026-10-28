import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../data/local/offline_model_dao.dart';

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

  /// Belt-and-braces ceiling for the whole install future.
  static const Duration _installTimeout = Duration(minutes: 30);

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

  static const String _modelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task';
  static const String _modelType = 'gemma3-1b-it-int4';

  /// Channel to the host MainActivity for the Android 13+ runtime
  /// POST_NOTIFICATIONS request (no permission_handler dependency).
  /// Best-effort only: denial merely hides the foreground notification,
  /// the download itself still runs.
  static const MethodChannel _notificationsChannel = MethodChannel(
    'com.agenta.agenta/notifications',
  );

  /// The effective download URL (env override wins). Shared by the install
  /// path and [ensureModelActive] so the plugin's idempotency key (derived
  /// from the URL filename) always matches.
  static String get resolvedModelUrl =>
      AppConfig.gemmaModelUrl.isNotEmpty ? AppConfig.gemmaModelUrl : _modelUrl;

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

  /// One-time migration: the broken third-party mirror and official file share
  /// the filename `gemma3-1b-it-int4.task`, so install() skips the official
  /// copy unless the old file is removed. Marker set BEFORE uninstall so a
  /// crash never loops the download.
  static Future<void> _migrateStaleAssetIfPresent() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('model_asset_v2') == true) return;
    final dao = OfflineModelDao();
    final hasActive = FlutterEdgeAi.hasActiveModel();
    final daoReady = await dao.isModelReady();
    if (!hasActive && !daoReady) return;
    await prefs.setBool('model_asset_v2', true);
    try {
      await FlutterEdgeAi.uninstallModel('gemma3-1b-it-int4.task');
    } catch (_) {
      // Already unregistered / file missing — safe to continue.
    }
    await dao.setModelNotInstalled();
  }

  Future<void> installModel() async {
    if (_status == ModelStatus.installing || _status == ModelStatus.ready) {
      return;
    }
    await _migrateStaleAssetIfPresent();
    await checkModelExists();
    if (_status == ModelStatus.ready) return;

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
      // ~529MB transfer alive when the app is backgrounded (WorkManager
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
          : FlutterEdgeAi.installModel(modelType: ModelType.gemmaIt)
                .fromNetwork(
                  resolvedModelUrl,
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
      await _dao.setModelReady(modelType: _modelType);
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
        await _dao.setModelReady(modelType: _modelType);
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
    if (FlutterEdgeAi.hasActiveModel()) return true;
    try {
      await FlutterEdgeAi.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(
            resolvedModelUrl,
            token: AppConfig.hfToken.trim(),
            foreground: AppConfig.foregroundDownload,
          )
          .install()
          .timeout(const Duration(minutes: 30));
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
