import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/local_user_dao.dart';
import '../../data/models/user_profile_model.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/recovery_code_hasher.dart';

/// Writes the `profiles` row and returns how many rows changed.
/// 0 means the write was blocked (RLS) or the row does not exist — the
/// caller must abort instead of continuing.
typedef ProfileDisplayNameWriter =
    Future<int> Function(String uid, String displayName);

/// Writes the `display_name` Auth metadata.
typedef AuthDisplayNameWriter = Future<void> Function(String displayName);

/// Why a display-name save failed (cycle-37 P4). Every value is a distinct
/// outcome; the edit screen shows one honest failure message for all of
/// them, the reason exists for the debug log and the tests.
enum DisplayNameSaveFailure {
  /// The profiles row write threw (network / server error).
  profileRowFailed,

  /// The profiles row write changed no row — blocked by RLS or no such row.
  /// The Auth metadata was NOT written, so the two stores never diverge.
  profileRowBlocked,

  /// The profiles row was written but the Auth metadata write failed.
  authFailed,
}

/// Thrown by [DisplayNameSaver.save] on every failure. The message is short,
/// factual and free of payloads (error hygiene: docs/error-hygiene.md);
/// the raw cause stays in the debug log only.
class DisplayNameSaveException implements Exception {
  const DisplayNameSaveException(this.failure, this.message);

  final DisplayNameSaveFailure failure;
  final String message;

  @override
  String toString() => 'DisplayNameSaveException(${failure.name}): $message';
}

/// Cycle-37 P4: the display-name save, split into its three writes so every
/// outcome is observable and testable.
///
/// The old one-liner wrote the profiles row, ignored how many rows it
/// changed and never checked the Auth write: an RLS-blocked row write
/// still updated the Auth metadata (meta-new / DB-old) and a failed Auth
/// write left the two stores silently out of sync.
class DisplayNameSaver {
  DisplayNameSaver({
    required this.writeProfileRow,
    required this.writeAuthMetadata,
    LocalUserDao? localUserDao,
  }) : _localUserDao = localUserDao ?? LocalUserDao();

  /// Writes the authoritative `profiles` row; returns the number of rows
  /// that changed (0 = blocked).
  final ProfileDisplayNameWriter writeProfileRow;

  /// Writes the `display_name` Auth metadata.
  final AuthDisplayNameWriter writeAuthMetadata;

  final LocalUserDao _localUserDao;

  /// Saves [displayName] for [uid].
  ///
  /// Order: local copy → profiles row → Auth metadata.
  ///
  /// * The local copy goes first so an edit made without a network still
  ///   lands on the device (the offline / claim path reads it).
  /// * The profiles row is authoritative: exactly one row must change. Zero
  ///   rows means the write was blocked, and the save aborts BEFORE the
  ///   Auth write — the Auth metadata is never set to a value the database
  ///   does not hold.
  /// * The Auth metadata is written last; a failure there aborts with an
  ///   honest error instead of a silent partial success.
  ///
  /// Throws [DisplayNameSaveException] on every failure.
  Future<void> save({required String uid, required String displayName}) async {
    await _writeLocalCopy(uid, displayName);

    final int updated;
    try {
      updated = await writeProfileRow(uid, displayName);
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '[UserRepository] display-name row write failed: $e | $stack',
        );
      }
      throw const DisplayNameSaveException(
        DisplayNameSaveFailure.profileRowFailed,
        'The profile row could not be updated.',
      );
    }
    if (updated != 1) {
      throw DisplayNameSaveException(
        DisplayNameSaveFailure.profileRowBlocked,
        'The profile row update changed $updated rows (expected exactly 1).',
      );
    }

    try {
      await writeAuthMetadata(displayName);
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '[UserRepository] display-name Auth write failed: $e | $stack',
        );
      }
      throw const DisplayNameSaveException(
        DisplayNameSaveFailure.authFailed,
        'The account metadata could not be updated.',
      );
    }
  }

  /// Best-effort local mirror: the device copy is a cache, so a failure
  /// here is logged but never fails the save (the same rule the password
  /// hash upgrade follows).
  Future<void> _writeLocalCopy(String uid, String displayName) async {
    try {
      await _localUserDao.updateDisplayName(
        localId: uid,
        displayName: displayName,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '[UserRepository] local display-name update failed: $e | $stack',
        );
      }
    }
  }
}

class UserRepository {
  static SupabaseClient get _db => Supabase.instance.client;

  /// The production display-name saver (cycle-37 P4). The writes are
  /// injected so every outcome — row blocked, row failed, Auth failed — can
  /// be exercised without a live Supabase project.
  static final DisplayNameSaver _productionDisplayNameSaver = DisplayNameSaver(
    writeProfileRow: _writeProfileDisplayName,
    writeAuthMetadata: AuthService.updateDisplayName,
  );

  /// Test seam: replaces the saver [updateDisplayName] uses, so the shipped
  /// entry point itself can be driven without a live Supabase project.
  /// Null in production.
  @visibleForTesting
  static DisplayNameSaver? displayNameSaverOverride;

  static DisplayNameSaver get _displayNameSaver =>
      displayNameSaverOverride ?? _productionDisplayNameSaver;

  /// Writes the `profiles` row and returns how many rows changed.
  ///
  /// `.select()` on the update builder is the supabase-dart v2 idiom for
  /// "did this update hit anything" (postgrest 2.9.1): the server returns
  /// the updated rows, so an RLS-blocked write comes back as an empty list
  /// instead of a silent success.
  static Future<int> _writeProfileDisplayName(
    String uid,
    String displayName,
  ) async {
    final rows = await _db
        .from('profiles')
        .update({'display_name': displayName})
        .eq('id', uid)
        .select('id');
    return rows.length;
  }

  // H8: raw recovery codes are shown once at creation only. What is
  // persisted (Supabase `recovery_code` column + local DB) is the SHA-256
  // hash. Target is a server-side RPC `verify_recovery_code` so the hash
  // never needs client-side comparison; until the RPC lands, compare
  // hashes for a single row (never a full-table fetch).

  static Future<void> createUserProfile(
    String uid,
    String email,
    String displayName,
    String recoveryCode,
  ) async {
    await _db.from('profiles').upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'recovery_code': RecoveryCodeHasher.hash(recoveryCode),
    });
  }

  /// Claim path for accounts first created offline: the local row only ever
  /// held the recovery-code *hash* (H8), so store that hash verbatim instead
  /// of hashing again — otherwise the code the user saved would stop matching.
  static Future<void> createUserProfileWithRecoveryHash(
    String uid,
    String email,
    String displayName,
    String recoveryCodeHash,
  ) async {
    await _db.from('profiles').upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'recovery_code': recoveryCodeHash,
    });
  }

  static Future<UserProfileModel?> getUserProfile(String uid) async {
    final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) return null;
    return UserProfileModel.fromMap(Map<String, dynamic>.from(row), uid);
  }

  /// Saves the display name for [uid] across the three stores that hold
  /// it: the device copy, the `profiles` row and the Auth metadata.
  ///
  /// Throws [DisplayNameSaveException] when any of the two server writes
  /// fails or when the row write changed no row — the edit screen turns
  /// that into its honest failure message.
  static Future<void> updateDisplayName(String uid, String displayName) async {
    await _displayNameSaver.save(uid: uid, displayName: displayName);
  }

  static Future<String> getRecoveryCodeHash() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      throw Exception('No user logged in');
    }
    final row = await _db
        .from('profiles')
        .select('recovery_code')
        .eq('id', uid)
        .maybeSingle();
    final hash = row?['recovery_code'] as String?;
    if (hash == null || hash.isEmpty) {
      throw Exception('Recovery code not found');
    }
    return hash;
  }

  /// Preferred server-side verification stub (H8). Replace the body with
  /// `await _db.rpc('verify_recovery_code', params: {...})` once the
  /// function in supabase/migrations/*_rls.sql is deployed; never trust
  /// a client-supplied userId — the RPC must use auth.uid().
  static Future<bool> verifyRecoveryCodeViaRpc(String entered) async {
    try {
      final storedHash = await getRecoveryCodeHash();
      return RecoveryCodeHasher.verify(entered, storedHash);
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '[UserRepository] verifyRecoveryCodeViaRpc failed: $e | $stack',
        );
      }
      return false;
    }
  }

  static Future<bool> verifyRecoveryCode(String entered) {
    return verifyRecoveryCodeViaRpc(entered);
  }
}
