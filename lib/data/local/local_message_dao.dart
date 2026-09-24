import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';
import '../models/chat_message_model.dart';
import '../../services/auth/session_manager.dart';

class LocalMessageDao {
  LocalMessageDao._();
  static final LocalMessageDao instance = LocalMessageDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<String> getUserIdAsync() async {
    try {
      final supabaseUid = Supabase.instance.client.auth.currentUser?.id;
      if (supabaseUid != null && supabaseUid.isNotEmpty) return supabaseUid;
    } catch (e) {
      // L20: supabase client may be unavailable offline — log and fall
      // through to the local-session fallback instead of silently dropping.
      if (kDebugMode) debugPrint('[LocalMessageDao] supabase uid read failed: $e');
    }
    try {
      final session = await SessionManager.currentSession();
      if (session != null) return session.uid;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalMessageDao] local session read failed: $e');
    }
    return '';
  }

  Future<void> insert(ChatMessageModel msg) async {
    final db = await _dbHelper.database;
    await db.insert('messages', msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatMessageModel>> getByChat(String chatId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'messages',
      where: 'chat_id = ? AND is_deleted = 0',
      whereArgs: [chatId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(ChatMessageModel.fromMap).toList();
  }

  Future<void> update(ChatMessageModel msg) async {
    final db = await _dbHelper.database;
    await db.update(
      'messages',
      msg.toMap(),
      where: 'id = ?',
      whereArgs: [msg.id],
    );
  }

  Future<void> markDeletedByChat(String chatId) async {
    final db = await _dbHelper.database;
    await db.update(
      'messages',
      {'is_deleted': 1, 'is_synced': 0},
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<void> hardDeleteByChat(String chatId) async {
    final db = await _dbHelper.database;
    await db.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
  }

  Future<List<ChatMessageModel>> getUnsynced() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'messages',
      where: 'is_synced = 0 AND is_deleted = 0',
    );
    return rows.map(ChatMessageModel.fromMap).toList();
  }

  Future<void> replaceMessagesPreservingUnsynced(List<ChatMessageModel> messages) async {
    if (messages.isEmpty) return;
    final db = await _dbHelper.database;

    const chunkSize = 500;
    final ids = messages.map((m) => m.id).toList();
    final Set<String> unsyncedIds = {};

    for (int i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'messages',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
        columns: ['id', 'is_synced', 'is_deleted'],
      );
      for (final row in rows) {
        if (row['is_synced'] == 0 || row['is_deleted'] == 1) {
          unsyncedIds.add(row['id'] as String);
        }
      }
    }

    final toInsert = messages.where((m) => !unsyncedIds.contains(m.id)).toList();
    if (toInsert.isEmpty) return;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final msg in toInsert) {
        batch.insert('messages', msg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Migrates message ownership after an offline → Supabase claim.
  ///
  /// Local `messages` rows are scoped by `chat_id` (no `user_id` column —
  /// see `DatabaseHelper._onCreate`); migrating the parent `chat_sessions`
  /// rows already re-homes every message. This probes `PRAGMA table_info`
  /// first: if a future schema adds `messages.user_id`, it is updated with
  /// the same pattern as `LocalChatDao.migrateUserId`; otherwise it is a
  /// safe no-op so callers (`SyncService`, login claim) never crash with
  /// "no such column: user_id".
  Future<void> migrateUserId(String oldUserId, String newUserId) async {
    if (oldUserId == newUserId) return;
    final db = await _dbHelper.database;
    final cols = await db.rawQuery('PRAGMA table_info(messages)');
    final hasUserId =
        cols.any((c) => (c['name'] as String?) == 'user_id');
    if (!hasUserId) {
      if (kDebugMode) {
        debugPrint('[LocalMessageDao] migrateUserId no-op '
            '(no user_id column; parent chat migration covers messages)');
      }
      return;
    }
    await db.update(
      'messages',
      {'user_id': newUserId},
      where: 'user_id = ?',
      whereArgs: [oldUserId],
    );
  }
}