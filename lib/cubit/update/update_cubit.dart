import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/update/version_check_service.dart';
import '../../services/update/version_source.dart';

/// Update-dialog status (Adviser contract).
enum UpdateStatus { idle, checking, available, forced }

/// State of the update dialog feature.
class UpdateState {
  final UpdateStatus status;

  /// Running app version, e.g. "1.1.0" (from package_info_plus). Empty when unknown.
  final String currentVersion;

  /// Running app build number (from package_info_plus). 0 when unknown.
  final int currentBuild;

  final RemoteRelease? remote;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.currentVersion = '',
    this.currentBuild = 0,
    this.remote,
  });

  bool get isForced => status == UpdateStatus.forced;

  /// Whether the dialog should be shown for this state (Adviser show rules):
  ///  - forced → always show, no dismiss;
  ///  - available → show only if [dismissedVersion] != remote.version
  ///    (a newer release automatically re-triggers the dialog).
  bool shouldShow(String? dismissedVersion) {
    if (status == UpdateStatus.forced) return true;
    if (status == UpdateStatus.available) {
      final version = remote?.version;
      return version == null || dismissedVersion != version;
    }
    return false;
  }

  UpdateState copyWith({
    UpdateStatus? status,
    String? currentVersion,
    int? currentBuild,
    RemoteRelease? remote,
  }) {
    return UpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      currentBuild: currentBuild ?? this.currentBuild,
      remote: remote ?? this.remote,
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
/// [UpdateStatus], and persists dismissals via the NEW `SharedPreferencesAsync`
/// API under [dismissedVersionKey] (not the legacy singleton).
///
/// Show rules (Adviser): forced → always show, no dismiss; available → show
/// only if the persisted dismissal != remote.version — a newer release
/// automatically re-triggers the dialog. Results arriving before the persisted
/// dismissal loads are buffered and applied once it does, so an already
/// dismissed version can never flash the dialog.
class UpdateCubit extends Cubit<UpdateState> {
  /// shared_preferences key = the remote version the user dismissed.
  static const String dismissedVersionKey = 'update_dismissed_version';

  final VersionCheckService _service;
  StreamSubscription<UpdateCheckResult>? _subscription;
  String? _dismissedVersion;
  bool _dismissalLoaded = false;
  UpdateCheckResult? _pendingResult; // result seen before the dismissal loaded

  UpdateCubit({VersionCheckService? service})
      : _service = service ?? VersionCheckService.instance,
        super(const UpdateState()) {
    _init();
  }

  /// The remote version the user dismissed (null = none).
  String? get dismissedVersion => _dismissedVersion;

  void _init() {
    _subscription = _service.resultStream.listen(_onResult);
    // Seed from a result the service may already have emitted (e.g. the check
    // ran before this cubit was created).
    final last = _service.lastResult;
    if (last != null) _onResult(last);
    _loadDismissal();
  }

  Future<void> _loadDismissal() async {
    try {
      // SharedPreferencesAsync (new API, not the legacy singleton). Its
      // constructor throws StateError when the platform is unset (unit tests),
      // so construction is covered by the same defensive guard.
      final prefs = SharedPreferencesAsync();
      final dismissed = await prefs.getString(dismissedVersionKey);
      _dismissedVersion =
          (dismissed == null || dismissed.isEmpty) ? null : dismissed;
    } catch (e) {
      // Defensive: unreadable prefs must never block the feature.
      _dismissedVersion = null;
      _log('[UpdateCubit] dismissal load failed: $e');
    } finally {
      _dismissalLoaded = true;
      // Apply a result that arrived while the persisted value was loading.
      final pending = _pendingResult;
      _pendingResult = null;
      if (pending != null) _applyResult(pending);
    }
  }

  void _onResult(UpdateCheckResult result) {
    if (!_dismissalLoaded) {
      _pendingResult = result;
      return;
    }
    _applyResult(result);
  }

  /// Maps a fresh service result → status per the Adviser show rules.
  void _applyResult(UpdateCheckResult result) {
    switch (result.level) {
      case UpdateLevel.forced:
        emit(_fromResult(result, UpdateStatus.forced));
      case UpdateLevel.available:
        if (_dismissedVersion == result.remote?.version) {
          // Dismissed for exactly this version — stay idle; a NEWER release
          // re-triggers the dialog.
          emit(_fromResult(result, UpdateStatus.idle));
        } else {
          emit(_fromResult(result, UpdateStatus.available));
        }
      case UpdateLevel.none:
        emit(_fromResult(result, UpdateStatus.idle));
    }
  }

  /// Force a network check now (user-initiated — the service still enforces
  /// its backoff/debug gates). While the call runs the state is
  /// [UpdateStatus.checking]; a silent failure/throttle returns to idle so the
  /// UI never gets stuck on "checking".
  Future<void> checkNow() async {
    emit(state.copyWith(status: UpdateStatus.checking));
    final result = await _service.checkNow();
    if (result == null) {
      if (state.status == UpdateStatus.checking) {
        emit(state.copyWith(status: UpdateStatus.idle));
      }
    }
    // Non-null: the resultStream listener has already mapped it (the service
    // adds the result before returning; applying again is idempotent).
  }

  /// Dismisses the dialog for the currently-shown remote version: persists
  /// [dismissedVersionKey] via `SharedPreferencesAsync` and returns to idle.
  /// A newer release automatically re-triggers the dialog (the dismissal only
  /// suppresses the exact version). Forced updates cannot be dismissed.
  Future<void> dismissUntilNextVersion() async {
    final remote = state.remote;
    if (state.status == UpdateStatus.forced || remote == null) return;
    final version = remote.version;
    try {
      await SharedPreferencesAsync().setString(dismissedVersionKey, version);
      _dismissedVersion = version;
    } catch (e) {
      // Persist failure — still dismiss in memory for this session.
      _dismissedVersion = version;
      _log('[UpdateCubit] dismissal persist failed: $e');
    }
    emit(state.copyWith(status: UpdateStatus.idle));
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
    _subscription?.cancel();
    return super.close();
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
