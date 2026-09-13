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
    final db = await _dbHelper.database;
    await db.insert('pending_signups', {
      'local_id': localId,
      'email': email,
      'password': password,
      'display_name': displayName,
      'recovery_code': recoveryCode,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'provider': provider,
      'password_salt': passwordSalt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    final rows = await db.query('pending_signups',
        where: 'email = ? AND is_synced = 0', whereArgs: [email]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await _dbHelper.database;
    final rows = await db.query('pending_signups',
        where: 'email = ?', whereArgs: [email]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> markUserSyncedByEmail(String email, String supabaseUid) async {
    final db = await _dbHelper.database;
    await db.update(
      'pending_signups',
      {'is_synced': 1, 'local_id': supabaseUid},
      where: 'email = ?',
      whereArgs: [email],
    );
  }
}