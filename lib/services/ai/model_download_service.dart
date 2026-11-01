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

/// The plugin-side facts the load-path repair reads (cycle-44 P2, branch A).
///
/// ONE seam for every probe, so the gate seam ([ModelDownloadService
/// .checkModelExists]) and the load seam ([ModelDownloadService
/// .ensureModelActive]) can never disagree about the state — a
/// self-inconsistent repair is exactly the loop the ruling forbids.
///
/// Every read answers "unknown" (null) rather than guessing when the
/// plugin cannot be reached: an UNREAD state is not a clean state, and the
/// repair must never turn an unknown into a destructive decision.
abstract class OfflineModelPlugin {
  /// The ids of every installed model — the persisted filenames.
  ///
  /// Null when the plugin could not be read (never "no models").
  Future<List<String>?> listInstalledModels();

  /// Whether the plugin holds an active inference model.
  bool hasActiveModel();

  /// The active model's identity (the plugin's spec name), or null when
  /// there is no active model.
  String? activeModelSpecName();

  /// Whether the model FILE [fileName] is installed.
  ///
  /// The plugin keys a model by its persisted filename. Null when the probe
  /// could not answer.
  Future<bool?> isModelInstalled(String fileName);

  /// Removes a model's files and metadata. Throws on an unknown id.
  Future<void> uninstallModel(String modelId);

  /// Clears the active inference identity (in-memory spec + persisted
  /// preferences).
  Future<void> clearActiveInferenceIdentity();
}

/// The production [OfflineModelPlugin] — the pinned flutter_edge_ai facade.
///
/// The reads are wrapped: the plugin is not initialized in a unit test and
/// a platform call can fail. A failed read yields "unknown", never a
/// destructive guess.
class FlutterEdgeAiModelPlugin implements OfflineModelPlugin {
  const FlutterEdgeAiModelPlugin();

  @override
  Future<List<String>?> listInstalledModels() async {
    try {
      return await FlutterEdgeAi.listInstalledModels();
    } catch (_) {
      return null;
    }
  }

  @override
  bool hasActiveModel() {
    try {
      return FlutterEdgeAi.hasActiveModel();
    } catch (_) {
      return false;
    }
  }

  @override
  String? activeModelSpecName() {
    try {
      return FlutterEdgeAi.activeModelSpec?.name;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> isModelInstalled(String fileName) async {
    try {
      return await FlutterEdgeAi.isModelInstalled(fileName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> uninstallModel(String modelId) =>
      FlutterEdgeAi.uninstallModel(modelId);

  @override
  Future<void> clearActiveInferenceIdentity() =>
      FlutterEdgeAi.clearActiveInferenceIdentity();
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

  // ── cycle-44 P2 (branch A): the load-path repair ─────────────────────────
  //
  // The plugin restores the previously-active model from the persisted
  // FILENAME alone (`mobile_model_manager.dart:155-222`) — it never checks
  // that filename against the app's SELECTED spec. A surviving legacy
  // `gemma3-1b-it-int4.task` was therefore resurrected as the answering
  // model while the app believed the Qwen asset was ready. The repair lives
  // at TWO seams (the gate seam and the load seam) and reads the plugin
  // through ONE seam, so the two never disagree.

  /// The plugin seam the repair reads (test-only override).
  ///
  /// Production talks to the pinned plugin; a test injects a fake so the
  /// repair's decisions are driven by a KNOWN state, never by a platform
  /// channel that is absent in a unit test.
  @visibleForTesting
  static OfflineModelPlugin? pluginOverrideForTest;

  static OfflineModelPlugin get _plugin =>
      pluginOverrideForTest ?? const FlutterEdgeAiModelPlugin();

  /// The selected asset's persisted filename — the id the plugin keys the
  /// model by.
  ///
  /// The derivation is the plugin's OWN: the install builder takes the
  /// model file's name from the source URL's last path segment
  /// (`inference_model_spec.dart:32` — `Uri.parse(url).pathSegments.last`)
  /// and uses it as BOTH the download target and the persisted model id
  /// (`inference_installation_builder.dart:435-438`), so the app's selected
  /// filename and the plugin's model id are the SAME string. The
  /// `AppConfig.gemmaModelUrl` override derives the same way, so the
  /// override stays legal (its own filename becomes the selected one).
  ///
  /// An EMPTY result means the URL carries no file name: the selected
  /// identity is UNKNOWN then, and the reconciliation treats that as
  /// unknown state (no mutation, no marker) — never as "everything is
  /// foreign".
  static String selectedFileNameFor(OfflineModelSpec spec) {
    final segments = Uri.parse(resolvedModelUrlFor(spec)).pathSegments;
    return segments.isEmpty ? '' : segments.last;
  }

  /// Whether [candidate] names the same model FILE as [fileName].
  ///
  /// The pinned plugin names a model in TWO representations (verified
  /// first-hand against flutter_edge_ai 1.11.4):
  ///
  /// * the RESTORE path rebuilds the active spec from the persisted
  ///   FILENAME (`mobile_model_manager.dart:215-220` —
  ///   `InferenceModelSpec(name: filename, ...)`), so the active spec's
  ///   name is `model.task`;
  /// * the INSTALL path names the spec after the extension-stripped
  ///   basename (`inference_installation_builder.dart:419` —
  ///   `FileNameUtils.getBaseName(...)`), so the active spec's name is
  ///   `model`.
  ///
  /// Both name the SAME file, so the repair compares MODEL IDENTITIES and
  /// never raw strings: a raw-string comparison would call the app's own
  /// freshly installed model "foreign" and clear a healthy identity (and
  /// would re-run the install chain on every load).
  ///
  /// The comparison is deliberately one-directional: [candidate] may be the
  /// stripped form of [fileName], but a candidate that carries a DIFFERENT
  /// extension is a different model and never matches.
  static bool isSameModelIdentity(String? candidate, String? fileName) {
    if (candidate == null || fileName == null) return false;
    if (candidate == fileName) return true;
    return candidate == _pluginBaseName(fileName);
  }

  /// The model's identity without its file extension — the plugin's own
  /// `FileNameUtils.getBaseName` (`file_name_utils.dart:47-53`), which
  /// strips every supported extension, in the plugin's own order.
  static String _pluginBaseName(String fileName) => fileName
      .replaceAll('.task', '')
      .replaceAll('.bin', '')
      .replaceAll('.tflite', '')
      .replaceAll('.json', '')
      .replaceAll('.model', '')
      .replaceAll('.litertlm', '');

  /// Migration v5 — the load-path reconciliation (cycle-44 P2, branch A).
  ///
  /// Three state-keyed legs, ONE pass per call:
  ///
  /// * **(a) foreign FILE** — every installed id that is not the selected
  ///   spec's filename is swept. The id-set comparison covers the
  ///   both-assets and any-legacy compositions by construction — there is
  ///   no hardcoded filename list. On the message-only class (no legal
  ///   asset) EVERY id is foreign.
  /// * **(b) foreign ACTIVE** — the plugin's active model is not the
  ///   selected spec. The identity is cleared: the plugin's
  ///   `uninstallModel` does NOT clear the identity, so this call is what
  ///   stops the in-process binding AND the next-launch resurrection.
  /// * **(c) the LIE** — the DAO row claims the asset is installed while
  ///   BOTH plugin probes agree it is gone. The composite probe is
  ///   normative: a single lying probe can then never loop the download
  ///   (after a real install the restore re-activates the selected file,
  ///   which makes the third conjunct false).
  ///
  /// The marker `model_asset_v5` is the VERIFIED-CLEAN record — a ruled
  /// deviation from the marker-first pattern (v2/v3/v4 needed marker-first
  /// because their bodies could trigger a download; v5's body never
  /// downloads, and marker-first would strand a needed repair after a
  /// partial failure — the exact defect class that produced this bug). It
  /// is written ONLY after the body proved the state clean, and when it is
  /// set ONLY leg (a) is skipped: legs (b) and (c) are state-keyed and run
  /// on every launch, so a needed repair is never stranded behind a stale
  /// marker.
  static Future<void> _reconcileSelectedSpecIfPresent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final spec = await OfflineModelSpecTable.currentSpec();
      final selectedFileName = spec == null ? null : selectedFileNameFor(spec);
      // A selected asset whose filename cannot be derived is an UNKNOWN
      // state: never sweep (every id would look foreign), never mark.
      if (selectedFileName != null && selectedFileName.isEmpty) return;
      final markerSet = prefs.getBool('model_asset_v5') == true;

      // The plugin facts, read ONCE — the three legs must agree.
      final installedIds = await _plugin.listInstalledModels();
      if (installedIds == null) return; // UNKNOWN state: no mutation, no marker
      final activeName = _plugin.activeModelSpecName();
      final hasActive = _plugin.hasActiveModel();

      // leg (a) — the foreign files.
      final foreignIds = installedIds
          .where((id) => id != selectedFileName)
          .toList(growable: false);

      // leg (b) — the foreign active model.
      final foreignActive =
          hasActive && !isSameModelIdentity(activeName, selectedFileName);

      // leg (c) — the lie. BOTH plugin probes must agree that the selected
      // asset is gone; a single lying probe can never loop the download.
      final fileInstalled = selectedFileName == null
          ? null
          : await _plugin.isModelInstalled(selectedFileName);
      final daoClaimsInstalled = await OfflineModelDao().isModelInstalled();
      final lie =
          daoClaimsInstalled &&
          fileInstalled == false &&
          !isSameModelIdentity(activeName, selectedFileName);

      // 1. SWEEP (leg a) — skipped only when the marker records a clean
      //    state. Tolerant: the plugin throws 'Model not found' on an
      //    unknown id, and a failed uninstall is retried on the next
      //    launch, never inside this call.
      final sweptIds = <String>[];
      if (!markerSet) {
        for (final id in foreignIds) {
          try {
            await _plugin.uninstallModel(id);
            sweptIds.add(id);
          } catch (_) {
            // Already unregistered / file missing — safe to continue.
          }
        }
      }

      // 2. IDENTITY — cleared when the active model is foreign, or when the
      //    sweep removed the active model's OWN file (the plugin leaves the
      //    identity pointing at a deleted file otherwise).
      final sweptTheActiveFile = sweptIds.any(
        (id) => isSameModelIdentity(activeName, id),
      );
      if (foreignActive || sweptTheActiveFile) {
        await _plugin.clearActiveInferenceIdentity();
      }

      // 3. THE LIE — the DAO reconciles to plugin truth, so the gate's
      //    readiness read honestly offers the fresh install.
      if (lie) {
        await OfflineModelDao().setModelNotInstalled();
      }

      // 4. VERIFY + MARKER — the marker is the verified-clean record. A
      //    state that is still not clean is NOT marked and NOT retried
      //    within the call (one pass per invocation; the next launch
      //    retries — idempotent, bounded).
      final remaining = await _plugin.listInstalledModels();
      if (remaining == null) return;
      final clean = remaining.every((id) => id == selectedFileName);
      if (clean) await prefs.setBool('model_asset_v5', true);
    } catch (e) {
      // A reconciliation must never break the download gate. The marker is
      // written only after a verified-clean state, so a failed pass is
      // retried on the next launch.
      if (kDebugMode) {
        debugPrint('[ModelDownload] v5 reconciliation failed: $e');
      }
    }
  }

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
    // The v5 reconciliation (cycle-44 P2, branch A) runs at the SAME seam —
    // after v3/v4, BEFORE the readiness read: it sweeps a foreign file,
    // clears a foreign active identity and resets a lying DB row, so the
    // readiness read below reads a reconciled state.
    await _reconcileSelectedSpecIfPresent();

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
      // ~1.6GB transfer alive when the app is backgrounded (WorkManager
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

  /// Re-establishes the plugin's active-model spec for this process — and
  /// VERIFY that the active model IS the app's selected asset
  /// (cycle-44 P2, branch A).
  ///
  /// On flutter_edge_ai 1.11.4, initialize() auto-restores the
  /// previously-active model identity from SharedPreferences — from the
  /// persisted FILENAME alone (`mobile_model_manager.dart:155-222`), never
  /// checked against the app's selected spec. A surviving legacy
  /// `gemma3-1b-it-int4.task` was therefore resurrected as the answering
  /// model while the app believed the Qwen asset was ready, and the old
  /// `hasActiveModel()` early-return below blessed that mismatch forever.
  ///
  /// The early return is therefore a VERIFIED match: the active model must
  /// BE the selected asset AND the asset's file must be present. Anything
  /// else runs the repair sequence — clear the foreign identity, then the
  /// idempotent install, which ends in the plugin's own `setActiveModel`
  /// (the activation) and overwrites the stale persisted identity.
  ///
  /// ONE repair pass per call (S1): the reconciliation and the install run
  /// at most once here, never in a loop.
  static Future<bool> ensureModelActive() async {
    await _migrateStaleAssetIfPresent();
    await _migrateLegacyAssetIfPresent();
    await _migrateStrandedE2bAssetIfPresent();
    // The v5 reconciliation runs at the LOAD seam too — the same shared
    // helper the gate seam calls, so the two seams can never disagree about
    // the state (a self-inconsistent repair is the loop the ruling forbids).
    await _reconcileSelectedSpecIfPresent();

    // The asset this device runs — the selection table decides. The
    // message-only class has none: nothing can be rehydrated there.
    final spec = await OfflineModelSpecTable.currentSpec();
    if (spec == null) return false;

    final selectedFileName = selectedFileNameFor(spec);
    if (await _activeModelIsSelected(selectedFileName)) return true;

    try {
      // A foreign active spec is cleared BEFORE the install: the plugin's
      // uninstallModel does NOT clear the identity, so this call is what
      // stops the in-process binding and the next-launch resurrection. The
      // install chain below then ends in setActiveModel, which overwrites
      // the stale persisted identity.
      if (_plugin.hasActiveModel()) {
        await _plugin.clearActiveInferenceIdentity();
      }
      await _installSelectedSpec(spec);
      return _plugin.hasActiveModel();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ModelDownload] ensureModelActive failed: $e');
      }
      return false;
    }
  }

  /// Whether the plugin's active model IS the selected asset and the
  /// asset's file is present.
  ///
  /// BOTH conjuncts are needed: a restored identity can name the right
  /// model while the file is gone (the DAO/plugin lie the device scout
  /// found), and the file can be present while a FOREIGN model is active.
  static Future<bool> _activeModelIsSelected(String selectedFileName) async {
    if (!_plugin.hasActiveModel()) return false;
    if (!isSameModelIdentity(_plugin.activeModelSpecName(), selectedFileName)) {
      return false;
    }
    final installed = await _plugin.isModelInstalled(selectedFileName);
    return installed == true;
  }

  /// The idempotent install chain of the selected spec.
  ///
  /// The plugin's own path: it skips the download when the file is already
  /// in the plugin's storage and ends in `setActiveModel` — the activation
  /// (the modern install path, `inference_installation_builder.dart:478`).
  static Future<void> _installSelectedSpec(OfflineModelSpec spec) async {
    final override = ensureInstallOverrideForTest;
    if (override != null) {
      await override(spec);
      return;
    }
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
  }

  /// Overrides the load-path install chain (test-only). When set,
  /// [_installSelectedSpec] calls it instead of the plugin.
  @visibleForTesting
  static Future<void> Function(OfflineModelSpec spec)?
  ensureInstallOverrideForTest;

  String? get errorMessage => _errorMessage;
}
