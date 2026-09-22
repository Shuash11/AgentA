import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../../core/config/app_config.dart';
import '../../data/local/offline_model_dao.dart';
import 'kaggle_download_service.dart';

enum ModelStatus { notInstalled, installing, ready, error }

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

  ModelStatus get status => _status;
  double get progress => _progress;
  bool get isReady => _status == ModelStatus.ready;
  bool get isSlowConnection => _isSlowConnection;

  static const String _modelUrl =
      'https://huggingface.co/AfiOne/gemma3-1b-it-int4.task/resolve/main/gemma3-1b-it-int4.task';
  static const String _modelType = 'gemma3-1b-it-int4';

  /// Channel to the host MainActivity for the Android 13+ runtime
  /// POST_NOTIFICATIONS request (no permission_handler dependency).
  /// Best-effort only: denial merely hides the foreground notification,
  /// the download itself still runs.
  static const MethodChannel _notificationsChannel =
      MethodChannel('com.agenta.agenta/notifications');

  /// The effective download URL (env override wins). Shared by the install
  /// path and [ensureModelActive] so the plugin's idempotency key (derived
  /// from the URL filename) always matches.
  static String get resolvedModelUrl =>
      AppConfig.gemmaModelUrl.isNotEmpty ? AppConfig.gemmaModelUrl : _modelUrl;

  bool get canUseKaggle =>
      AppConfig.kaggleUsername.isNotEmpty && AppConfig.kaggleKey.isNotEmpty;

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
      final secondsSinceLastUpdate = now.difference(_lastProgressTime!).inSeconds;
      if (secondsSinceLastUpdate > 60 && !_isSlowConnection) {
        _isSlowConnection = true;
        notifyListeners();
      }
    }
    _notifyProgress();
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
          // FlutterGemma.hasActiveModel() here — that spec is in-memory only
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

  Future<void> installModel() async {
    if (_status == ModelStatus.installing || _status == ModelStatus.ready) return;

    await checkModelExists();
    if (_status == ModelStatus.ready) return;

    _status = ModelStatus.installing;
    _progress = 0.0;
    _errorMessage = null;
    _lastProgressTime = null;
    _isSlowConnection = false;
    _lastProgressValue = 0.0;
    _lastNotifiedProgress = -1.0;
    notifyListeners();

    // Android 13+ shows the foreground-service progress notification only
    // with the runtime POST_NOTIFICATIONS grant. Best-effort: denial never
    // blocks the download, it only hides the notification.
    await _ensureNotificationPermission();

    try {
      // foreground: true keeps the ~529MB transfer alive when the app is
      // backgrounded (WorkManager alone is subject to background limits).
      // Timeout stays as belt-and-braces.
      // install() is idempotent (skips the download when the file is already
      // in the plugin's storage) and resolves only AFTER finalization, when
      // the active spec is set. Completing early — at the 100% progress
      // event — raced the plugin's file move and left the gate stuck, so
      // readiness is marked strictly after this future resolves.
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(resolvedModelUrl, foreground: true)
          .withProgress(_onDownloadProgress)
          .install()
          .timeout(const Duration(minutes: 30));

      _progress = 100.0;
      await _dao.setModelReady(modelType: _modelType);
      _status = ModelStatus.ready;
    } catch (e) {
      // Tolerance: some devices close the connection right after the final
      // byte while the install future unwinds. If the transfer reached 100%,
      // the file is complete — settle briefly and mark ready (load-time
      // rehydration covers any residual plugin-side finalization).
      if (_progress >= 100.0) {
        await Future.delayed(const Duration(seconds: 2));
        await _dao.setModelReady(modelType: _modelType);
        _status = ModelStatus.ready;
        if (kDebugMode) {
          debugPrint('[ModelDownload] install failed at 100% — treated as complete: $e');
        }
      } else {
        _applyDownloadFailure(e, logTag: 'installModel');
      }
    }

    notifyListeners();
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS runtime grant via the host
  /// MainActivity. Always returns quickly; false (denied, non-Android, or
  /// channel unavailable e.g. in widget tests) never blocks the download.
  Future<bool> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _notificationsChannel
          .invokeMethod<bool>('requestNotificationPermission');
      return granted ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ModelDownload] notification permission request failed: $e');
      }
      return false;
    }
  }

  /// Maps a download/install failure to a friendly, brand-free UI state.
  /// flutter_gemma 1.x throws typed [DownloadException] (switch over its
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
      debugPrint('[ModelDownload] $logTag failed '
          '(typed=${error is DownloadException}, retryable=$retryable): $error');
    }
  }

  /// Returns the user-facing message for [error], or null when the failure
  /// should stay silent (user cancellation).
  String? _friendlyDownloadError(Object error) {
    if (error is DownloadException) {
      return switch (error.error) {
        NotFoundError() =>
          'The offline model file could not be found at its source. Check the download link.',
        UnauthorizedError() || ForbiddenError() =>
          'The model source rejected the download.',
        RateLimitedError() =>
          'Too many download attempts. Try again later.',
        NetworkError() =>
          'No internet connection. Download will resume when you are back online.',
        CanceledError() => null,
        ServerError() || UnknownError() =>
          'Download failed. Please try again.',
      };
    }
    if (error is TimeoutException) {
      return 'Download timed out. Please try again.';
    }
    return 'Download failed. Please try again.';
  }

  /// Re-establishes the plugin's active-model spec for this process.
  /// On flutter_gemma 1.8.4, initialize() already auto-restores the
  /// previously-active model identity from SharedPreferences, so
  /// hasActiveModel() is usually true at startup and this returns early.
  /// The install() below is the defensive remainder: it is idempotent
  /// (skips the download when the file is already in the plugin's storage)
  /// and transparently re-downloads — as a foreground service — when the
  /// storage was lost or prefs restore failed.
  static Future<bool> ensureModelActive() async {
    if (FlutterGemma.hasActiveModel()) return true;
    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(resolvedModelUrl, foreground: true)
          .install()
          .timeout(const Duration(minutes: 30));
      return FlutterGemma.hasActiveModel();
    } catch (e) {
      if (kDebugMode) debugPrint('[ModelDownload] ensureModelActive failed: $e');
      return false;
    }
  }

  Future<void> installModelFromKaggle() async {
    if (!canUseKaggle) {
      _errorMessage = 'Kaggle credentials not configured';
      notifyListeners();
      return;
    }

    if (_status == ModelStatus.installing || _status == ModelStatus.ready) return;

    await checkModelExists();
    if (_status == ModelStatus.ready) return;

    _status = ModelStatus.installing;
    _progress = 0.0;
    _errorMessage = null;
    _lastProgressTime = null;
    _isSlowConnection = false;
    _lastProgressValue = 0.0;
    _lastNotifiedProgress = -1.0;
    notifyListeners();

    try {
      final kaggle = createKaggleService();
      
      // Kaggle model reference for Gemma 3 1B
      const modelRef = 'google/gemma-3/flax';
      
      final filePath = await kaggle.downloadModel(
        modelRef: modelRef,
        framework: 'gemma3',
        instanceSlug: '1b-it-int4',
        onProgress: (progress) {
          _progress = progress;
          _notifyProgress();
        },
      );

      if (filePath != null) {
        // The Kaggle download is a local file on disk, NOT a bundled Flutter
        // asset — fromAsset() would fail to resolve it. fromFile() installs
        // from the filesystem.
        await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
            .fromFile(filePath)
            .install();

        _progress = 100.0;
        await _dao.setModelReady(modelType: _modelType);
        _status = ModelStatus.ready;
      } else {
        _status = ModelStatus.error;
        _errorMessage = 'Failed to download from Kaggle';
        await _dao.setModelError('Failed to download from Kaggle');
      }
    } catch (e) {
      // fromFile().install() throws typed DownloadException for plugin-side
      // failures; the Kaggle fetch itself throws plain errors. Both map to
      // friendly states — raw detail stays in debugPrint.
      _applyDownloadFailure(e, logTag: 'kaggle install');
    }

    notifyListeners();
  }

  String? get errorMessage => _errorMessage;

  Future<bool> hasUserSkipped() async {
    return await _dao.hasUserSkipped();
  }
}
