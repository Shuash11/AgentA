import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

    try {
      // install() is idempotent (skips the download when the file is already
      // in the plugin's storage) and resolves only AFTER finalization, when
      // the active spec is set. Completing early — at the 100% progress
      // event — raced the plugin's file move and left the gate stuck, so
      // readiness is marked strictly after this future resolves.
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(resolvedModelUrl)
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
        _status = ModelStatus.error;
        _errorMessage = e.toString();
        await _dao.setModelError(e.toString());
        if (kDebugMode) debugPrint('[ModelDownload] installModel failed: $e');
      }
    }

    notifyListeners();
  }

  /// Rehydrates the plugin's in-memory active-model spec after a process
  /// restart. [FlutterGemma.getActiveModel] throws StateError until
  /// install()/setActiveModel has run in THIS process. install() is
  /// idempotent: when the model file is already in the plugin's private
  /// storage it skips the download and only sets the active spec — so this
  /// is cheap whenever the model is truly on disk, and it transparently
  /// re-downloads when the storage was lost.
  static Future<bool> ensureModelActive() async {
    if (FlutterGemma.hasActiveModel()) return true;
    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(resolvedModelUrl)
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
      _status = ModelStatus.error;
      _errorMessage = e.toString();
      await _dao.setModelError(e.toString());
      if (kDebugMode) debugPrint('[ModelDownload] kaggle install failed: $e');
    }

    notifyListeners();
  }

  String? get errorMessage => _errorMessage;

  Future<bool> hasUserSkipped() async {
    return await _dao.hasUserSkipped();
  }
}
