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
  Future<String?> _existingRecoveryCodeHash(String localId, String email) async {
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

  Future<List<Map<String, dynamic>>> getPendingSignups() async {
    final db = await _dbHelper.database;
    return await db.query('pending_signups',
        where: 'is_synced = 0',
        orderBy: 'created_at ASC');
  }

  Future<Map<String, dynamic>?> getPendingSignupByLocalId(String localId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('pending_signups',
        where: 'local_id = ?', whereArgs: [localId]);
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
    await db.delete('pending_signups',
        where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<Map<String, dynamic>?> getPendingSignupByEmail(String email) async {
    final db = await _dbHelper.database;
    // Emails are compared case-insensitively: Supabase lowercases addresses,
    // but a device may hold rows written with the user's original casing.
    final rows = await db.query('pending_signups',
        where: 'email = ? COLLATE NOCASE AND is_synced = 0',
        whereArgs: [email]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await _dbHelper.database;
    final rows = await db.query('pending_signups',
        where: 'email = ? COLLATE NOCASE', whereArgs: [email]);
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