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

  Future<void> checkModelExists() async {
    if (_status == ModelStatus.installing) return;

    final oldStatus = _status;
    final oldProgress = _progress;

    try {
      final sqliteReady = await _dao.isModelReady();
      

      if (sqliteReady) {
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
          final hasActiveModel = FlutterGemma.hasActiveModel();
          if (hasActiveModel) {
            _status = ModelStatus.ready;
            _progress = 100.0;
            
          } else if (_status != ModelStatus.installing) {
            _status = ModelStatus.notInstalled;
            _progress = 0.0;
          }
        }
      } else {
        _status = ModelStatus.notInstalled;
        _progress = 0.0;
        
      }
    } catch (e) {
       
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

    final url = AppConfig.gemmaModelUrl.isNotEmpty ? AppConfig.gemmaModelUrl : _modelUrl;
    final completer = Completer<void>();

    try {
      final installFuture = FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
      ).fromNetwork(url).withProgress((progress) {
        _progress = progress.toDouble();
        
        // Check for slow connection (60s without progress increase)
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
        
        if (_progress >= 100.0) {
          _status = ModelStatus.ready;
          _dao.setModelReady(modelType: 'gemma3-1b-it-int4', filePath: null);
          if (!completer.isCompleted) completer.complete();
        }
        _notifyProgress();
      }).install();

      // We complete if the install future finishes OR progress reaches 100%
      installFuture.then((_) {
        _status = ModelStatus.ready;
        _progress = 100.0;
        _dao.setModelReady(modelType: 'gemma3-1b-it-int4', filePath: null);
        if (!completer.isCompleted) completer.complete();
        _notifyProgress();
      }).catchError((e) {
        // If we're already at 100%, ignore minor connection closure errors
        if (_progress < 100.0) {
          if (!completer.isCompleted) completer.completeError(e);
        } else {
          if (!completer.isCompleted) completer.complete();
        }
      });

      // Increase timeout significantly. 500MB can take several minutes on slow connections.
      await completer.future.timeout(const Duration(minutes: 20));
      
      // Give time for model extraction to complete (async process)
      // Then retry hasActiveModel() a few times with backoff
      await _waitForModelReady(filePath: null);
    } catch (e) {
      await _waitForModelReady(filePath: null);
      if (!isReady) {
        _status = ModelStatus.error;
        _errorMessage = e.toString();
        await _dao.setModelError(e.toString());
      }
    }

    notifyListeners();
  }

  Future<void> _waitForModelReady({String? filePath}) async {
    await Future.delayed(const Duration(seconds: 3));

    for (int attempt = 0; attempt < 2; attempt++) {
      final hasActiveModel = FlutterGemma.hasActiveModel();
      

      if (hasActiveModel) {
        final oldStatus = _status;
        final oldProgress = _progress;
        await _dao.setModelReady(
          modelType: 'gemma3-1b-it-int4',
          filePath: filePath,
        );
        _status = ModelStatus.ready;
        _progress = 100.0;
        
        _notifyStateChanged(oldStatus, oldProgress);
        return;
      }
      await Future.delayed(Duration(seconds: (2 << attempt)));
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
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromAsset(filePath).install();

        await _waitForModelReady(filePath: filePath);

        if (isReady) {
          
        } else {
          _status = ModelStatus.error;
          _errorMessage = 'Model installed but failed to initialize';
          await _dao.setModelError('Model installed but failed to initialize');
        }
      } else {
        _status = ModelStatus.error;
        _errorMessage = 'Failed to download from Kaggle';
        await _dao.setModelError('Failed to download from Kaggle');
      }
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = e.toString();
      await _dao.setModelError(e.toString());
    }

    notifyListeners();
  }

  String? get errorMessage => _errorMessage;

  Future<bool> hasUserSkipped() async {
    return await _dao.hasUserSkipped();
  }
}
