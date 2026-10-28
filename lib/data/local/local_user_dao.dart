import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class LocalUserDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> savePendingSignup({
    required String localId,
    required String email,
    required String password,
    required String displayName,
    required String recoveryCode,
    bool isSynced = false,
    String provider = 'password',
    String passwordSalt = '',
  }) async {
    // When the incoming recovery code is empty (e.g. online login
    // re-saves the local row without a new code), preserve the existing
    // recovery-code hash so a successful login never overwrites it.
    var effectiveRecoveryCode = recoveryCode;
    if (effectiveRecoveryCode.isEmpty) {
      final existing = await _existingRecoveryCodeHash(localId, email);
      if (existing != null) effectiveRecoveryCode = existing;
    }

    final db = await _dbHelper.database;
    await db.insert('pending_signups', {
      'local_id': localId,
      'email': email,
      'password': password,
      'display_name': displayName,
      'recovery_code': effectiveRecoveryCode,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'provider': provider,
      'password_salt': passwordSalt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Existing recovery-code hash for this account, preferring the row with
  /// the same [localId]; null when no row holds a non-empty hash.
  Future<String?> _existingRecoveryCodeHash(
    String localId,
    String email,
  ) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pending_signups',
      where: '(local_id = ? OR email = ? COLLATE NOCASE)',
      whereArgs: [localId, email],
    );
    String? fallback;
    for (final row in rows) {
      final code = row['recovery_code'] as String?;
      if (code == null || code.isEmpty) continue;
      if (row['local_id'] == localId) return code;
      fallback ??= code;
    }
    return fallback;
  }

  /// Replaces the stored password hash for [localId] from [expectedHash] to
  /// [newHash] (compare-and-swap in a single atomic UPDATE). The CAS guard
  /// means a row that changed since the caller fetched it is left untouched.
  /// Returns the number of rows updated (0 when the row is absent or its
  /// hash no longer equals [expectedHash]).
  ///
  /// [newHash] is a self-describing PHC string, so the legacy
  /// `password_salt` column is cleared.
  Future<int> upgradePasswordHash({
    required String localId,
    required String expectedHash,
    required String newHash,
  }) async {
    final db = await _dbHelper.database;
    return db.update(
      'pending_signups',
      {'password': newHash, 'password_salt': ''},
      where: 'local_id = ? AND password = ?',
      whereArgs: [localId, expectedHash],
    );
  }

  /// Best-effort wrapper for [upgradePasswordHash]: never throws, so a failed
  /// hash upgrade can never block an already-successful login. Returns true
  /// when the row was upgraded. Migration-style failure handling per
  /// docs/error-hygiene.md (debug log only).
  Future<bool> tryUpgradePasswordHash({
    required String localId,
    required String expectedHash,
    required String newHash,
  }) async {
    try {
      final updated = await upgradePasswordHash(
        localId: localId,
        expectedHash: expectedHash,
        newHash: newHash,
      );
      return updated > 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalUserDao] password-hash upgrade failed: $e');
      }
      return false;
    }
  }

  /// Compare-and-swap password-hash update for a never-synced offline
  /// account (cycle-31 P4), mirroring [upgradePasswordHash] with one extra
  /// invariant in the guard: the row must still be `is_synced = 0`.
  ///
  /// A concurrent sync flips `is_synced` (and remaps `local_id`), so this
  /// update can never overwrite the credential of a row that no longer lives
  /// on the device alone. Returns the number of rows updated (0 = row
  /// absent, synced, or its hash no longer equals [expectedHash] — the
  /// caller must not claim success).
  Future<int> updateUnsyncedPasswordHash({
    required String localId,
    required String expectedHash,
    required String newHash,
  }) async {
    final db = await _dbHelper.database;
    return db.update(
      'pending_signups',
      {'password': newHash, 'password_salt': ''},
      where: 'local_id = ? AND password = ? AND is_synced = 0',
      whereArgs: [localId, expectedHash],
    );
  }

  /// Updates the stored display name of the account row [localId].
  ///
  /// Cycle-37 P4 (defect D): the profile edit must reach the device copy
  /// too, otherwise an offline account keeps the name it was created with
  /// and every local read of the name is stale.
  ///
  /// The row is addressed by [localId] (the `pending_signups.local_id`
  /// primary key), never by email — an edit can therefore only ever touch
  /// the account that made it, even when several rows share an address.
  /// Returns the number of rows updated: 0 means this device holds no row
  /// for that account, so the caller must not claim the name was saved.
  Future<int> updateDisplayName({
    required String localId,
    required String displayName,
  }) async {
    final db = await _dbHelper.database;
    return db.update(
      'pending_signups',
      {'display_name': displayName},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSignups() async {
    final db = await _dbHelper.database;
    return await db.query(
      'pending_signups',
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getPendingSignupByLocalId(
    String localId,
  ) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pending_signups',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> markAsSynced(String localId, String supabaseUid) async {
    final db = await _dbHelper.database;
    await db.update(
      'pending_signups',
      {'is_synced': 1, 'local_id': supabaseUid},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> delete(String localId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'pending_signups',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<Map<String, dynamic>?> getPendingSignupByEmail(String email) async {
    final db = await _dbHelper.database;
    // Emails are compared case-insensitively: Supabase lowercases addresses,
    // but a device may hold rows written with the user's original casing.
    final rows = await db.query(
      'pending_signups',
      where: 'email = ? COLLATE NOCASE AND is_synced = 0',
      whereArgs: [email],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pending_signups',
      where: 'email = ? COLLATE NOCASE',
      whereArgs: [email],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> markUserSyncedByEmail(String email, String supabaseUid) async {
    final db = await _dbHelper.database;
    await db.update(
      'pending_signups',
      {'is_synced': 1, 'local_id': supabaseUid},
      where: 'email = ? COLLATE NOCASE',
      whereArgs: [email],
    );
  }
}
