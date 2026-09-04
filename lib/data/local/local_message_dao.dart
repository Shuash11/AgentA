import 'package:sqflite/sqflite.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'database_helper.dart';
import '../models/chat_message_model.dart';

class LocalMessageDao {
  LocalMessageDao._();
  static final LocalMessageDao instance = LocalMessageDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  String getUserId() => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<String> getUserIdAsync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
    await user?.reload();
    return FirebaseAuth.instance.currentUser?.uid ?? '';
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

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
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

  Future<void> deleteByChat(String chatId) async {
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

  Future<void> replaceMessage(String messageId, ChatMessageModel msg) async {
    final db = await _dbHelper.database;
    await db.insert('messages', msg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> migrateUserId(String oldUserId, String newUserId) async {
    final db = await _dbHelper.database;
    await db.update(
      'messages',
      {'chat_id': newUserId},
      where: 'chat_id = ?',
      whereArgs: [oldUserId],
    );
  }
}