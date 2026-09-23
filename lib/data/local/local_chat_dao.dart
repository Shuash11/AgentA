import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';
import '../models/chat_session_model.dart';
import '../../services/auth/session_manager.dart';

class LocalChatDao {
  LocalChatDao._();
  static final LocalChatDao instance = LocalChatDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<String> getUserId() async {
    try {
      final supabaseUid = Supabase.instance.client.auth.currentUser?.id;
      if (supabaseUid != null && supabaseUid.isNotEmpty) return supabaseUid;
    } catch (e) {
      // L20: supabase client may be unavailable offline — log and fall
      // through to the local-session fallback instead of silently dropping.
      if (kDebugMode) debugPrint('[LocalChatDao] supabase uid read failed: $e');
    }
    try {
      final session = await SessionManager.currentSession();
      if (session != null) return session.uid;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalChatDao] local session read failed: $e');
    }
    return '';
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

  /// Sync-path tombstone read: rows where `is_deleted = 1`.
  ///
  /// Reuses [getDeletedChats] so the previously dead query has a named
  /// entry point for the Phase 2 tombstone push.
  Future<List<ChatSessionModel>> getTombstonedChats() => getDeletedChats();

  /// Pure tombstone/unsynced guard for the replace helper.
  ///
  /// Returns true when a local row must never be overwritten from remote:
  /// unsynced local edits (`is_synced = 0`) or offline deletes
  /// (`is_deleted = 1`). Exposed for unit tests; the DB orchestration
  /// below stays thin.
  @visibleForTesting
  static bool shouldPreserveLocalRow({
    required int isSynced,
    required int isDeleted,
  }) {
    return isSynced == 0 || isDeleted == 1;
  }

  /// Pure unread preservation for the replace helper.
  ///
  /// Remote rows always map with `unread = 0`; the local badge count must
  /// survive a synced-row replacement. Exposed for unit tests.
  @visibleForTesting
  static ChatSessionModel withPreservedUnread(
    ChatSessionModel remote,
    int localUnread,
  ) {
    if (remote.unread == localUnread) return remote;
    return ChatSessionModel(
      id: remote.id,
      userId: remote.userId,
      title: remote.title,
      lastMessage: remote.lastMessage,
      updatedAt: remote.updatedAt,
      unread: localUnread,
      isSynced: remote.isSynced,
      isDeleted: remote.isDeleted,
    );
  }

  /// Pure ghost-chat guard for the downstream prune helper.
  ///
  /// Returns true only when a fully-synced, non-deleted local row is absent
  /// from the fetched remote set — a ghost left behind by a remote delete
  /// that arrived without a tombstone. Never true for unsynced rows (they
  /// may be pending upstream push) or tombstones (`is_deleted = 1`, handled
  /// by the existing tombstone prune loop). Exposed for unit tests.
  @visibleForTesting
  static bool shouldPruneLocalRow({
    required int isSynced,
    required int isDeleted,
    required bool existsRemotely,
  }) {
    return !existsRemotely && isSynced == 1 && isDeleted == 0;
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

  /// Batched remote refresh that never clobbers local state.
  ///
  /// Mirrors `LocalMessageDao.replaceMessagesPreservingUnsynced`: chunked
  /// (500) tombstone/unsynced probe, then a single transaction batch insert.
  /// Skips local rows with `is_synced = 0` or `is_deleted = 1`; for synced
  /// rows replaced from remote, the local `unread` count is preserved.
  /// Live callers (Phase 2): `SyncService` batched refresh and
  /// `ChatRepository.getChatsForUser` — both rely on the tombstone/unsynced
  /// skip so offline deletes and unsynced edits are never resurrected.
  Future<void> replaceChatsPreservingUnsynced(
    List<ChatSessionModel> chats,
  ) async {
    if (chats.isEmpty) return;
    final db = await _dbHelper.database;

    const chunkSize = 500;
    final ids = chats.map((c) => c.id).toList();
    final Set<String> skipIds = {};
    final Map<String, int> localUnread = {};

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = i + chunkSize > ids.length ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'chat_sessions',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
        columns: ['id', 'is_synced', 'is_deleted', 'unread'],
      );
      for (final row in rows) {
        final id = row['id'] as String;
        final isSynced = (row['is_synced'] as int?) ?? 0;
        final isDeleted = (row['is_deleted'] as int?) ?? 0;
        if (shouldPreserveLocalRow(
            isSynced: isSynced, isDeleted: isDeleted)) {
          skipIds.add(id);
        } else {
          localUnread[id] = (row['unread'] as int?) ?? 0;
        }
      }
    }

    final toInsert = <ChatSessionModel>[];
    for (final chat in chats) {
      if (skipIds.contains(chat.id)) continue;
      final preserved = localUnread[chat.id];
      if (preserved != null && preserved != chat.unread) {
        toInsert.add(withPreservedUnread(chat, preserved));
      } else {
        toInsert.add(chat);
      }
    }
    if (toInsert.isEmpty) return;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final chat in toInsert) {
        batch.insert('chat_sessions', chat.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Downstream ghost-chat prune.
  ///
  /// Live caller: `SyncService._refreshLocalCacheFromRemote` ghost-prune step
  /// (behind the `chatsFetched` guard) — prunes synced-but-alive rows absent
  /// remotely after the tombstone loop.
  ///
  /// Hard-deletes fully-synced, non-deleted local chats absent from the
  /// fetched remote set, plus their messages. Skips unsynced rows, tombstones
  /// (via [shouldPruneLocalRow]), and any chat still holding unsynced
  /// messages (same `is_synced = 0 AND is_deleted = 0` filter as
  /// `getUnsynced`) so pending local work is never destroyed. Callers must
  /// pass the complete remote id set and only call after a successful fetch
  /// (the `chatsFetched` guard in `SyncService`); an empty set therefore
  /// prunes every synced candidate. Returns the pruned chat count.
  Future<int> pruneChatsGoneRemote(Set<String> remoteChatIds) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'chat_sessions',
      columns: ['id', 'is_synced', 'is_deleted'],
    );
    if (rows.isEmpty) return 0;

    final unsyncedMsgRows = await db.query(
      'messages',
      distinct: true,
      columns: ['chat_id'],
      where: 'is_synced = 0 AND is_deleted = 0',
    );
    final chatsWithUnsynced = <String>{
      for (final row in unsyncedMsgRows) row['chat_id'] as String,
    };

    final toPrune = <String>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final isSynced = (row['is_synced'] as int?) ?? 0;
      final isDeleted = (row['is_deleted'] as int?) ?? 0;
      if (!shouldPruneLocalRow(
        isSynced: isSynced,
        isDeleted: isDeleted,
        existsRemotely: remoteChatIds.contains(id),
      )) {
        continue;
      }
      if (chatsWithUnsynced.contains(id)) continue;
      toPrune.add(id);
    }
    if (toPrune.isEmpty) return 0;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in toPrune) {
        batch.delete('messages', where: 'chat_id = ?', whereArgs: [id]);
        batch.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
    return toPrune.length;
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