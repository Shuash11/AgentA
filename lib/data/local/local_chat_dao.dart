import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'database_helper.dart';
import '../models/chat_session_model.dart';

class LocalChatDao {
  LocalChatDao._();
  static final LocalChatDao instance = LocalChatDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<String> getUserId() async {
    try {
      final offlineUser = await _secureStorage.read(key: 'offline_user');

      if (offlineUser == 'true') {
        final email = await _secureStorage.read(key: 'offline_email');
        if (email != null) {
          return _generateOfflineUserId(email);
        }
        return 'offline_user';
      }

      return Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  String _generateOfflineUserId(String email) {
    final bytes = utf8.encode(email);
    int hash = 0;
    for (var byte in bytes) {
      hash = ((hash << 5) - hash) + byte;
      hash = hash & 0xFFFFFFFF;
    }
    return 'offline_${hash.toRadixString(16)}';
  }

  Future<void> insert(ChatSessionModel chat) async {
    final db = await _dbHelper.database;
    await db.insert('chat_sessions', chat.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatSessionModel>> getByUserId(String userId) async {
    if (userId.isEmpty) {
      userId = await getUserId();
    }
    final db = await _dbHelper.database;
    final rows = await db.query(
      'chat_sessions',
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(ChatSessionModel.fromMap).toList();
  }

  Future<List<ChatSessionModel>> getAllChats() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'chat_sessions',
      where: 'is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(ChatSessionModel.fromMap).toList();
  }

  Future<List<ChatSessionModel>> getDeletedChats() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'chat_sessions',
      where: 'is_deleted = 1',
    );
    return rows.map(ChatSessionModel.fromMap).toList();
  }

  Future<ChatSessionModel?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return ChatSessionModel.fromMap(rows.first);
  }

  Future<void> update(ChatSessionModel chat) async {
    final db = await _dbHelper.database;
    await db.update(
      'chat_sessions',
      chat.toMap(),
      where: 'id = ?',
      whereArgs: [chat.id],
    );
  }

  Future<void> markDeleted(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'chat_sessions',
      {'is_deleted': 1, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDelete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatSessionModel>> getUnsynced() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'chat_sessions',
      where: 'is_synced = 0 AND is_deleted = 0',
    );
    return rows.map(ChatSessionModel.fromMap).toList();
  }

  Future<void> replaceChat(String chatId, ChatSessionModel chat) async {
    final db = await _dbHelper.database;
    await db.insert('chat_sessions', chat.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> migrateUserId(String oldUserId, String newUserId) async {
    final db = await _dbHelper.database;
    await db.update(
      'chat_sessions',
      {'user_id': newUserId},
      where: 'user_id = ?',
      whereArgs: [oldUserId],
    );
  }
}