import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/utils/connectivity_service.dart';
import '../../core/utils/semver.dart';
import 'github_releases_source.dart';
import 'version_source.dart';

/// Update state level exposed to the (Phase 2) dialog.
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

/// Owns update-check comparison + scheduling for the "new version has
/// arrived" feature.
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
/// `enabled: true` instead.
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
  bool _isChecking = false;
  AppLifecycleState? _lifecycleState;

  DateTime? _lastCheckAt; // last network call attempt — throttle gate
  DateTime? _lastSuccessfulCheckAt; // last successful response — cache timestamp
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
  })  : _source = source ?? GithubReleasesSource(),
        _connectivity = connectivity ?? ConnectivityService.instance,
        _enabled = enabled ?? kReleaseMode,
        _minCheckIntervalOverride = minCheckInterval;

  Duration get _minInterval => _minCheckIntervalOverride ?? _minCheckInterval;

  /// Last emitted result (state). Null until a fresh check produced an
  /// outcome; a failed/skipped check never overwrites it.
  UpdateCheckResult? get lastResult => _lastResult;

  /// Broadcast stream of fresh check outcomes (callback).
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

    // Fire-and-forget startup check — never blocks boot.
    unawaited(_runCheck(respectInterval: true));
  }

  /// Immediate, user-initiated check. Bypasses the 5-min throttle (it is
  /// explicit) but still respects the rate-limit backoff gate, the
  /// debug-build gate, and the in-flight reentrancy guard.
  Future<UpdateCheckResult?> checkNow() => _runCheck(respectInterval: false);

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
    _connectivitySubscription?.cancel();
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

  /// The single backoff/throttle gate every check passes through.
  Future<UpdateCheckResult?> _runCheck({required bool respectInterval}) async {
    if (!_enabled) return null;
    if (_isChecking) return _lastResult; // a check is already in flight

    // Rate-limit backoff: never retry until the deadline passes.
    if (_isBackedOff) {
      final until =
          _source is GithubReleasesSource ? _source.backoffUntil : null;
      _log('[Update] skip — rate-limit backoff until $until');
      return null;
    }

    // Min 5 min between network calls (automatic triggers only).
    if (respectInterval && _lastCheckAt != null) {
      final since = DateTime.now().difference(_lastCheckAt!);
      if (since < _minInterval) {
        _log('[Update] skip — throttled (min interval ${_minInterval.inMinutes}m)');
        return null;
      }
    }

    final current = SemVer.tryParse(_currentVersion ?? '');
    if (current == null) {
      _log('[Update] skip — current version unknown/unparseable');
      return null;
    }

    _isChecking = true;
    try {
      _lastCheckAt = DateTime.now();
      final remote = await _source.fetchLatestRelease();
      if (remote == null) {
        // 404 / rate-limited / network failure — no information. Do NOT emit:
        // a failed check must never clear or downgrade a previous state, and
        // null must never be read as "up to date".
        _log('[Update] no release info — no result emitted');
        return null;
      }

      // Cache the last successful response with its timestamp (inspection
      // only — never drives emitted results or UI).
      _cachedRelease = remote;
      _lastSuccessfulCheckAt = DateTime.now();

      final result = _decide(remote, current);
      _lastResult = result;
      _resultController.add(result);
      _log('[Update] level=${result.level.name} current=$_currentVersion remote=v${remote.version}');
      return result;
    } catch (e) {
      // Silent failure — debug log only.
      _log('[Update] check failed (silent): $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  bool get _isBackedOff {
    if (_source is! GithubReleasesSource) return false;
    final until = _source.backoffUntil;
    return until != null && until.isAfter(DateTime.now());
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
    final min =
        remote.minVersion == null ? null : SemVer.tryParse(remote.minVersion!);

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
  void setCurrentVersionForTest({required String version, required String build}) {
    _currentVersion = version;
    _currentBuild = build;
  }

  void dispose() {
    _periodicTimer?.cancel();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _resultController.close();
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
