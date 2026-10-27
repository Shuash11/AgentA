import 'package:flutter/foundation.dart';

import '../../data/local/local_user_dao.dart';
import 'biometric_auth_service.dart';
import 'offline_login_guard.dart';
import 'password_hasher.dart';
import 'session_manager.dart';

/// Why an offline password change did not complete. Every value is a
/// distinct user-visible outcome; the page maps them to copy.
enum OfflinePasswordChangeFailure {
  /// No local signed-in session (or an empty email): nothing to change.
  noSession,

  /// The session's local row is gone (e.g. removed after sustained failed
  /// attempts on the offline sign-in path).
  accountNotFound,

  /// The row is synced or not a password account: its credential lives with
  /// the online factor chain (P3), not on this device alone.
  accountRequiresOnline,

  /// [OfflineLoginGuard] lockout window is active for this email.
  lockedOut,

  /// The supplied current password did not match the stored hash.
  wrongPassword,

  /// The device-credential prompt was shown and not confirmed.
  deviceCancelled,

  /// The compare-and-swap row update matched no row: the credential (or the
  /// synced state) changed between the verify and the write.
  updateConflict,
}

/// Thrown by [OfflinePasswordService.updateLocalPassword] on every failure;
/// nothing is written to the row when it is thrown.
class OfflinePasswordChangeException implements Exception {
  const OfflinePasswordChangeException(this.reason);

  final OfflinePasswordChangeFailure reason;

  @override
  String toString() => 'OfflinePasswordChangeException(${reason.name})';
}

/// Cycle 31 · P4 — offline password change for never-synced accounts.
///
/// An account created offline and never synced (local row `is_synced = 0`,
/// provider `'password'`, no Supabase user) changes its password fully
/// on-device, with zero connectivity:
///
/// 1. knowledge factor — the current password is verified against the local
///    row with Argon2id ([PasswordHasher.verifyPassword], the same call the
///    offline sign-in path makes),
/// 2. possession factor — the device credential ("the phone's password"),
///    asked only when the device can show the prompt (pre-probe before the
///    prompt call). No screen lock degrades, never blocks — the P1 fail-open
///    policy; the knowledge factor above is still enforced,
/// 3. the new password is re-hashed with [PasswordHasher.hashPassword] and
///    written back through a compare-and-swap row update, so a row that
///    changed (including one a concurrent sync marked synced) is left
///    untouched and the caller never claims success.
///
/// Failed current-password attempts reuse [OfflineLoginGuard]: the same
/// per-email counting and 5-attempt lockout as the offline sign-in path
/// (the gate is checked before any failure is recorded). The 10-failure
/// credential wipe is inherited too, but as the guard's
/// intentionally-defensive backstop — unreachable through this gated path,
/// since the lockout plus the [OfflineLoginGuard.lockoutWindow] prune cap
/// the count at [OfflineLoginGuard.maxAttempts]. The active protection is
/// the lockout + window prune.
///
/// This file deliberately imports nothing from Supabase — the whole path
/// must work with the device in airplane mode.
class OfflinePasswordService {
  OfflinePasswordService({LocalUserDao? userDao})
    : _userDao = userDao ?? LocalUserDao();

  final LocalUserDao _userDao;

  /// True when this device can show a device-credential prompt (biometric or
  /// the phone's PIN/pattern/passcode). Uses the device-credential OR
  /// predicate (biometrics OR any secure lock, so PIN-only devices pass);
  /// false → the device step degrades (fail-open) and the caller shows the
  /// explanatory notice. The pre-probe runs before any prompt call (P3
  /// pattern): its `false` collapses "no prompt can be shown" into the
  /// degrade path.
  Future<bool> deviceCredentialPromptAvailable() =>
      BiometricAuthService.isDeviceCredentialPromptAvailable();

  /// Changes the signed-in never-synced account's local password.
  ///
  /// Proof order: current-password verify (knowledge factor) → device
  /// credential when available (possession factor) → re-hash with
  /// [PasswordHasher.hashPassword] + compare-and-swap write. Throws
  /// [OfflinePasswordChangeException] for every failure; on success the row
  /// holds a fresh Argon2id hash and nothing else about it changes.
  Future<void> updateLocalPassword({
    required String currentPassword,
    required String newPassword,
    required String localizedReason,
  }) async {
    final session = await SessionManager.currentSession();
    final email = session?.email.trim() ?? '';
    if (session == null || email.isEmpty) {
      throw const OfflinePasswordChangeException(
        OfflinePasswordChangeFailure.noSession,
      );
    }

    final row = await _userDao.getUserByEmail(email);
    if (row == null) {
      throw const OfflinePasswordChangeException(
        OfflinePasswordChangeFailure.accountNotFound,
      );
    }
    final provider = (row['provider'] as String?) ?? 'password';
    final isSynced = ((row['is_synced'] as int?) ?? 0) == 1;
    if (provider != 'password' || isSynced) {
      // Synced or Google-linked rows: the device copy is not the account's
      // credential — those classes change their password online (P3).
      throw const OfflinePasswordChangeException(
        OfflinePasswordChangeFailure.accountRequiresOnline,
      );
    }

    // Same rate-limit gate as the offline sign-in path.
    if (OfflineLoginGuard.isLockedOut(email)) {
      throw const OfflinePasswordChangeException(
        OfflinePasswordChangeFailure.lockedOut,
      );
    }

    final storedHash = (row['password'] as String?) ?? '';
    final storedSalt = (row['password_salt'] as String?) ?? '';
    final verification = PasswordHasher.verifyPassword(
      currentPassword,
      storedHash: storedHash,
      storedSalt: storedSalt,
    );
    if (!verification.matched) {
      await _recordFailure(email, row);
      throw const OfflinePasswordChangeException(
        OfflinePasswordChangeFailure.wrongPassword,
      );
    }
    // The knowledge factor passed: clear the failure window (same contract
    // as the offline sign-in path). A legacy row is upgraded by the write
    // below when the change completes.
    OfflineLoginGuard.clearFailures(email);

    // Possession factor — asked only when the device can show the prompt
    // (pre-probe). No screen lock → degrade (fail-open, P1 policy).
    if (await deviceCredentialPromptAvailable()) {
      final confirmed = await BiometricAuthService.confirmDeviceCredential(
        localizedReason: localizedReason,
      );
      if (!confirmed) {
        throw const OfflinePasswordChangeException(
          OfflinePasswordChangeFailure.deviceCancelled,
        );
      }
    }

    final newHash = PasswordHasher.hashPassword(newPassword);
    final updated = await _userDao.updateUnsyncedPasswordHash(
      localId: row['local_id'] as String,
      expectedHash: storedHash,
      newHash: newHash,
    );
    if (updated == 0) {
      // Lost the compare-and-swap race (concurrent change or sync): the row
      // keeps its old hash and the caller must not claim success.
      throw const OfflinePasswordChangeException(
        OfflinePasswordChangeFailure.updateConflict,
      );
    }
  }

  /// Records a failed current-password attempt with [OfflineLoginGuard].
  /// The wipe branch below is the guard's intentionally-defensive backstop:
  /// it is unreachable through this gated path ([updateLocalPassword] checks
  /// [OfflineLoginGuard.isLockedOut] before recording anything, and the
  /// window prune caps the count at [OfflineLoginGuard.maxAttempts]), so the
  /// active protection remains the 5-attempt lockout + prune. Only a caller
  /// bypassing the gate can trigger the wipe.
  Future<void> _recordFailure(String email, Map<String, dynamic> row) async {
    final shouldWipe = OfflineLoginGuard.recordFailure(email);
    if (!shouldWipe) return;
    try {
      final localId = row['local_id'] as String;
      await _userDao.delete(localId);
      await SessionManager.dropStashedPassword(localId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflinePasswordService] credential wipe failed: $e');
      }
    }
    OfflineLoginGuard.clearFailures(email);
  }
}
