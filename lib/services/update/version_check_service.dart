import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/utils/connectivity_service.dart';
import '../../core/utils/semver.dart';
import 'github_releases_source.dart';
import 'version_source.dart';

/// Update state level exposed to the dialog.
enum UpdateLevel { none, available, forced }

/// Outcome of a fresh version check (Adviser contract):
/// `{level: none|available|forced, currentVersion, currentBuild, remote}`.
class UpdateCheckResult {
  final UpdateLevel level;

  /// Running app version, e.g. "1.1.0". Null when PackageInfo failed.
  final String? currentVersion;

  /// Running app build number, e.g. "2". Recorded but NEVER compared.
  final String? currentBuild;

  final RemoteRelease? remote;

  const UpdateCheckResult({
    required this.level,
    this.currentVersion,
    this.currentBuild,
    this.remote,
  });

  @override
  String toString() =>
      'UpdateCheckResult(level: ${level.name}, current: $currentVersion+$currentBuild, remote: ${remote?.version})';
}

/// Classified outcome of a version check (contract §2). User-initiated
/// checks ([VersionCheckService.checkNow]) return it directly; automatic
/// paths discard it — failures and skips are silent by contract.
sealed class UpdateCheckOutcome {
  const UpdateCheckOutcome();
}

/// A fresh decision was produced; it has already been emitted on
/// [VersionCheckService.resultStream].
final class UpdateCheckCompleted extends UpdateCheckOutcome {
  final UpdateCheckResult result;

  const UpdateCheckCompleted(this.result);
}

/// The check failed before producing a decision. Failed checks never emit
/// on [VersionCheckService.resultStream] and never change dialog state.
final class UpdateCheckFailed extends UpdateCheckOutcome {
  final UpdateFailureReason reason;

  /// Rate-limit deadline — set iff [reason] is
  /// [UpdateFailureReason.rateLimited].
  final DateTime? retryAt;

  const UpdateCheckFailed(this.reason, {this.retryAt});
}

/// The check was not attempted (build gate, throttle, unknown current
/// version) — distinct from a failure: nothing was tried and nothing failed.
final class UpdateCheckSkipped extends UpdateCheckOutcome {
  final UpdateSkipReason reason;

  const UpdateCheckSkipped(this.reason);
}

/// Why a check failed (contract §2).
enum UpdateFailureReason {
  noRelease,
  rateLimited,
  offline,
  timeout,
  unexpected,
}

/// Why a check was not attempted (contract §2).
enum UpdateSkipReason { nonRelease, throttled, versionUnknown }

/// Owns update-check comparison + scheduling for the "new version has
/// arrived" feature.
///
/// Contract: `contracts/update-engine.yaml` (cycle-27, §2). Core rules:
///  - every fetch is classified ([VersionSource]); failures are only silent
///    on automatic paths, and only user-initiated checks surface them;
///  - automatic paths (startup, resumed, periodic, connectivity-restored)
///    emit NOTHING on failure or skip — `resultStream` carries completed
///    results only;
///  - [checkNow] joins an in-flight check and returns THAT check's outcome,
///    never a stale [lastResult].
///
/// Public API: [init] (must be called post-first-frame, never before
/// `runApp()` — `PackageInfo.fromPlatform` before the first frame is a known
/// plus_plugins issue #309 and can hang on some platforms), [checkNow], and
/// the update state via [lastResult] / [resultStream].
///
/// Scheduling — all automatic triggers go through the same backoff/throttle
/// gate in [_runCheck]:
///  - startup check — fire-and-forget, never blocks boot;
///  - re-check on `AppLifecycleState.resumed` — min 5 min between network calls;
///  - periodic timer every 30 min while foregrounded;
///  - connectivity-restored hook (via the existing [ConnectivityService]).
///
/// Checks are skipped entirely in debug/profile builds ([kReleaseMode] gate)
/// to avoid dev noise — unit tests inject a fake [VersionSource] with
/// `enabled: true` instead. A user-initiated check in such a build reports
/// [UpdateCheckSkipped] with [UpdateSkipReason.nonRelease].
///
/// The last successful response is cached in memory with a timestamp
/// ([cachedRelease] / [lastSuccessfulCheckAt]) for inspection only — the
/// cache NEVER drives emitted results or UI. Dialogs must only ever be
/// surfaced from a fresh network check, never from a stale cache.
class VersionCheckService with WidgetsBindingObserver {
  static const Duration _minCheckInterval = Duration(minutes: 5);
  static const Duration _periodicInterval = Duration(minutes: 30);

  final VersionSource _source;
  final ConnectivityService _connectivity;
  final bool _enabled;
  final Duration? _minCheckIntervalOverride;

  Timer? _periodicTimer;
  StreamSubscription<InternetStatus>? _connectivitySubscription;
  bool _initialized = false;
  Future<UpdateCheckOutcome>? _inFlight; // the running check, if any
  AppLifecycleState? _lifecycleState;

  DateTime? _lastCheckAt; // last network call attempt — throttle gate
  DateTime?
  _lastSuccessfulCheckAt; // last successful response — cache timestamp
  RemoteRelease? _cachedRelease; // last successful response — never drives UI

  String? _currentVersion;
  String? _currentBuild;

  UpdateCheckResult? _lastResult;
  final _resultController = StreamController<UpdateCheckResult>.broadcast();

  /// Lazily-created app-wide instance (repo convention, cf.
  /// `ConnectivityService.instance`). Source/connectivity defaults are used;
  /// unit tests construct their own instances with injected fakes.
  static final VersionCheckService instance = VersionCheckService();

  /// [source] is injectable for unit tests (fake [VersionSource]).
  /// [connectivity] defaults to [ConnectivityService.instance].
  /// [enabled] defaults to [kReleaseMode] — checks are skipped in
  /// debug/profile builds; tests pass `enabled: true` to exercise the engine.
  /// [minCheckInterval] overrides the 5-min throttle (test seam only).
  VersionCheckService({
    VersionSource? source,
    ConnectivityService? connectivity,
    bool? enabled,
    Duration? minCheckInterval,
  }) : _source = source ?? GithubReleasesSource(),
       _connectivity = connectivity ?? ConnectivityService.instance,
       _enabled = enabled ?? kReleaseMode,
       _minCheckIntervalOverride = minCheckInterval;

  Duration get _minInterval => _minCheckIntervalOverride ?? _minCheckInterval;

  /// Last emitted result (state). Null until a fresh check produced a
  /// decision; a failed/skipped check never overwrites it.
  UpdateCheckResult? get lastResult => _lastResult;

  /// Broadcast stream of fresh check outcomes (callback) — completed
  /// results only; failures and skips never emit (contract §2).
  Stream<UpdateCheckResult> get resultStream => _resultController.stream;

  /// Last successful response — inspection only. NEVER use this to surface
  /// a dialog: dialogs come from fresh checks only, never from a stale cache.
  RemoteRelease? get cachedRelease => _cachedRelease;

  /// When the last successful response was fetched. Null = no cache yet.
  DateTime? get lastSuccessfulCheckAt => _lastSuccessfulCheckAt;

  /// Loads the running app version and starts scheduling. Must be called
  /// post-first-frame (after the first frame rendered), never before
  /// `runApp()` — see plus_plugins #309.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _loadCurrentVersion();

    if (!_enabled) {
      _log('[Update] non-release build — checks disabled (kReleaseMode gate)');
      return;
    }

    _startScheduling();

    // Fire-and-forget startup check — never blocks boot. The outcome is
    // discarded: automatic paths stay silent on failure (contract §2).
    unawaited(_runCheck(respectInterval: true));
  }

  /// Immediate, user-initiated check. Bypasses the 5-min throttle (it is
  /// explicit) but still respects the build gate and the rate-limit backoff
  /// gate. When a check is already in flight, this JOINS it and returns that
  /// check's outcome — never a stale [lastResult].
  Future<UpdateCheckOutcome> checkNow() => _runCheck(respectInterval: false);

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = info.buildNumber;
      _log('[Update] current version ${info.version}+${info.buildNumber}');
    } catch (e) {
      // Unsupported platforms / unit tests — the current version can be
      // injected via [setCurrentVersionForTest]; checks skip without it.
      _log('[Update] PackageInfo.fromPlatform failed: $e');
    }
  }

  void _startScheduling() {
    // AppLifecycleState.resumed re-check.
    WidgetsBinding.instance.addObserver(this);

    // Connectivity-restored hook (existing ConnectivityService).
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = _connectivity.statusStream.listen((status) {
      if (status == InternetStatus.online) {
        _log('[Update] connectivity restored — checking (throttled)');
        unawaited(_runCheck(respectInterval: true));
      }
    });

    // Periodic check while foregrounded (tick gated on lifecycle state).
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      if (_lifecycleState == AppLifecycleState.resumed) {
        unawaited(_runCheck(respectInterval: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _log('[Update] app resumed — checking (throttled)');
      unawaited(_runCheck(respectInterval: true));
    }
  }

  /// The single backoff/throttle gate every check passes through. Returns
  /// the classified outcome; automatic callers discard it (silence).
  Future<UpdateCheckOutcome> _runCheck({required bool respectInterval}) {
    // A check is already in flight — join it (never a stale return).
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    if (!_enabled) {
      return Future.value(
        const UpdateCheckSkipped(UpdateSkipReason.nonRelease),
      );
    }

    // Rate-limit backoff: never retry until the deadline passes.
    final backoffUntil = _source.backoffUntil;
    if (backoffUntil != null && backoffUntil.isAfter(DateTime.now())) {
      _log('[Update] skip — rate-limit backoff until $backoffUntil');
      return Future.value(
        UpdateCheckFailed(
          UpdateFailureReason.rateLimited,
          retryAt: backoffUntil,
        ),
      );
    }

    // Min 5 min between network calls (automatic triggers only).
    if (respectInterval && _lastCheckAt != null) {
      final since = DateTime.now().difference(_lastCheckAt!);
      if (since < _minInterval) {
        _log(
          '[Update] skip — throttled (min interval ${_minInterval.inMinutes}m)',
        );
        return Future.value(
          const UpdateCheckSkipped(UpdateSkipReason.throttled),
        );
      }
    }

    final current = SemVer.tryParse(_currentVersion ?? '');
    if (current == null) {
      _log('[Update] skip — current version unknown/unparseable');
      return Future.value(
        const UpdateCheckSkipped(UpdateSkipReason.versionUnknown),
      );
    }

    final future = _executeCheck(current);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  /// Runs one network check and maps its classified fetch result to an
  /// outcome. Only a completed decision is cached and emitted (contract §2,
  /// `silence_contract`).
  Future<UpdateCheckOutcome> _executeCheck(SemVer current) async {
    _lastCheckAt = DateTime.now();
    try {
      final fetch = await _source.fetchLatestRelease();
      switch (fetch) {
        case ReleaseFetched(:final release):
          // Cache the last successful response with its timestamp
          // (inspection only — never drives emitted results or UI).
          _cachedRelease = release;
          _lastSuccessfulCheckAt = DateTime.now();

          final result = _decide(release, current);
          _lastResult = result;
          _resultController.add(result);
          _log(
            '[Update] level=${result.level.name} current=$_currentVersion remote=v${release.version}',
          );
          return UpdateCheckCompleted(result);
        case ReleaseNotFound():
          _log('[Update] no release info (404) — no result emitted');
          return const UpdateCheckFailed(UpdateFailureReason.noRelease);
        case ReleaseRateLimited(:final retryAt):
          _log('[Update] rate-limited until $retryAt — no result emitted');
          return UpdateCheckFailed(
            UpdateFailureReason.rateLimited,
            retryAt: retryAt,
          );
        case ReleaseOffline():
          _log('[Update] offline — no result emitted');
          return const UpdateCheckFailed(UpdateFailureReason.offline);
        case ReleaseTimedOut():
          _log('[Update] timed out — no result emitted');
          return const UpdateCheckFailed(UpdateFailureReason.timeout);
        case ReleaseUnexpected(:final statusCode):
          _log(
            '[Update] unexpected fetch result (status $statusCode) — no result emitted',
          );
          return const UpdateCheckFailed(UpdateFailureReason.unexpected);
      }
    } catch (e) {
      // Defensive only — a VersionSource never throws (contract §2).
      _log('[Update] check failed (unexpected): $e');
      return const UpdateCheckFailed(UpdateFailureReason.unexpected);
    }
  }

  /// Decision per the Adviser's rules:
  ///  - `minVersion != null && current < minVersion` → forced;
  ///  - else `latest > current` → available;
  ///  - else none.
  ///
  /// Build number is recorded but NOT compared (convention: every
  /// user-facing release bumps semver).
  UpdateCheckResult _decide(RemoteRelease remote, SemVer current) {
    final latest = SemVer.tryParse(remote.version);
    final min = remote.minVersion == null
        ? null
        : SemVer.tryParse(remote.minVersion!);

    var level = UpdateLevel.none;
    if (latest != null) {
      if (min != null && current.compareTo(min) < 0) {
        level = UpdateLevel.forced;
      } else if (latest.compareTo(current) > 0) {
        level = UpdateLevel.available;
      }
    }
    return UpdateCheckResult(
      level: level,
      currentVersion: _currentVersion,
      currentBuild: _currentBuild,
      remote: remote,
    );
  }

  /// Test hook — injects the current version without the platform channel.
  @visibleForTesting
  void setCurrentVersionForTest({
    required String version,
    required String build,
  }) {
    _currentVersion = version;
    _currentBuild = build;
  }

  void dispose() {
    _periodicTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_resultController.close());
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
