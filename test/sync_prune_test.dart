import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_chat_dao.dart';
import 'package:aiproject/data/local/local_message_dao.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/data/models/chat_session_model.dart';

// Phase 1 ghost-chat prune seam: pure-contract tests plus DB integration.
//
// Covers `LocalChatDao.shouldPruneLocalRow` and
// `LocalChatDao.pruneChatsGoneRemote` against a real in-memory database
// (`DatabaseHelper.testDatabase`). No `SyncService` callers change in this
// phase (wiring is Phase 2), so this file proves the DAO primitive only:
// ghosts (synced, alive, absent remotely) are hard-deleted with their
// messages, while unsynced rows, tombstones, and chats holding unsynced
// messages are never touched.

ChatSessionModel pruneChat({
  String id = 'c1',
  String userId = 'u1',
  bool isSynced = true,
  bool isDeleted = false,
}) {
  return ChatSessionModel(
    id: id,
    userId: userId,
    title: 't',
    lastMessage: 'm',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    isSynced: isSynced,
    isDeleted: isDeleted,
  );
}

ChatMessageModel pruneMessage({
  String id = 'm1',
  String chatId = 'c1',
  bool isSynced = true,
  bool isDeleted = false,
}) {
  return ChatMessageModel(
    id: id,
    chatId: chatId,
    text: 'hello',
    isUser: true,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    isSynced: isSynced,
    isDeleted: isDeleted,
  );
}

Future<void> createPruneSchema(Database db) async {
  await db.execute('''
    CREATE TABLE chat_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      last_message TEXT,
      updated_at INTEGER NOT NULL,
      unread INTEGER DEFAULT 0,
      is_synced INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      chat_id TEXT NOT NULL,
      text TEXT NOT NULL,
      is_user INTEGER NOT NULL,
      timestamp INTEGER NOT NULL,
      is_synced INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0,
      FOREIGN KEY (chat_id) REFERENCES chat_sessions(id)
        ON DELETE CASCADE
    )
  ''');
}

void main() {
  late Database db;
  final chatDao = LocalChatDao.instance;
  final msgDao = LocalMessageDao.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async => createPruneSchema(db),
      ),
    );
    DatabaseHelper.testDatabase = db;
  });

  tearDownAll(() async {
    DatabaseHelper.clearTestDatabase();
    await db.close();
  });

  setUp(() async {
    await db.delete('messages');
    await db.delete('chat_sessions');
  });

  group('shouldPruneLocalRow ghost guard', () {
    test('synced + alive + absent remotely is pruned', () {
      expect(
        LocalChatDao.shouldPruneLocalRow(
          isSynced: 1,
          isDeleted: 0,
          existsRemotely: false,
        ),
        true,
      );
    });

    test('synced + alive + present remotely is kept', () {
      expect(
        LocalChatDao.shouldPruneLocalRow(
          isSynced: 1,
          isDeleted: 0,
          existsRemotely: true,
        ),
        false,
      );
    });

    test('unsynced rows are never pruned, even when absent remotely', () {
      expect(
        LocalChatDao.shouldPruneLocalRow(
          isSynced: 0,
          isDeleted: 0,
          existsRemotely: false,
        ),
        false,
      );
    });

    test('unsynced rows present remotely are never pruned', () {
      expect(
        LocalChatDao.shouldPruneLocalRow(
          isSynced: 0,
          isDeleted: 0,
          existsRemotely: true,
        ),
        false,
      );
    });

    test('tombstones are never pruned (existing loop owns them)', () {
      expect(
        LocalChatDao.shouldPruneLocalRow(
          isSynced: 1,
          isDeleted: 1,
          existsRemotely: false,
        ),
        false,
      );
      expect(
        LocalChatDao.shouldPruneLocalRow(
          isSynced: 0,
          isDeleted: 1,
          existsRemotely: false,
        ),
        false,
      );
    });
  });

  group('pruneChatsGoneRemote DB integration (ffi)', () {
    test('synced row absent remotely is pruned with its messages', () async {
      await chatDao.insert(pruneChat(id: 'ghost'));
      await msgDao.insert(pruneMessage(id: 'm1', chatId: 'ghost'));
      await msgDao.insert(pruneMessage(id: 'm2', chatId: 'ghost'));

      final pruned = await chatDao.pruneChatsGoneRemote({'other-chat'});

      expect(pruned, 1);
      expect(await chatDao.getById('ghost'), isNull);
      expect(
        await db.query('messages', where: 'chat_id = ?', whereArgs: ['ghost']),
        isEmpty,
      );
    });

    test('unsynced row absent remotely is preserved', () async {
      await chatDao.insert(pruneChat(id: 'pending', isSynced: false));

      final pruned = await chatDao.pruneChatsGoneRemote({'other-chat'});

      expect(pruned, 0);
      expect(await chatDao.getById('pending'), isNotNull);
    });

    test('synced row present remotely is untouched', () async {
      await chatDao.insert(pruneChat(id: 'alive'));
      await msgDao.insert(pruneMessage(id: 'm1', chatId: 'alive'));

      final pruned = await chatDao.pruneChatsGoneRemote({'alive'});

      expect(pruned, 0);
      expect(await chatDao.getById('alive'), isNotNull);
      expect(
        await db.query('messages', where: 'chat_id = ?', whereArgs: ['alive']),
        hasLength(1),
      );
    });

    test('tombstone absent remotely is left for the existing loop', () async {
      await chatDao.insert(
        pruneChat(id: 'tomb', isSynced: true, isDeleted: true),
      );

      final pruned = await chatDao.pruneChatsGoneRemote({'other-chat'});

      expect(pruned, 0);
      expect(
        (await chatDao.getTombstonedChats()).map((c) => c.id),
        contains('tomb'),
      );
    });

    test('chat with unsynced message absent remotely is preserved', () async {
      await chatDao.insert(pruneChat(id: 'busy'));
      await msgDao.insert(
        pruneMessage(id: 'synced-m', chatId: 'busy', isSynced: true),
      );
      await msgDao.insert(
        pruneMessage(id: 'unsent-m', chatId: 'busy', isSynced: false),
      );

      final pruned = await chatDao.pruneChatsGoneRemote({'other-chat'});

      expect(pruned, 0);
      expect(await chatDao.getById('busy'), isNotNull);
      expect(
        await db.query(
          'messages',
          where: 'chat_id = ? AND id = ?',
          whereArgs: ['busy', 'unsent-m'],
        ),
        hasLength(1),
      );
    });

    test('mixed batch prunes only the ghost', () async {
      await chatDao.insert(pruneChat(id: 'ghost'));
      await msgDao.insert(pruneMessage(id: 'm-ghost', chatId: 'ghost'));
      await chatDao.insert(pruneChat(id: 'alive'));
      await chatDao.insert(pruneChat(id: 'pending', isSynced: false));
      await chatDao.insert(
        pruneChat(id: 'tomb', isSynced: true, isDeleted: true),
      );

      final pruned = await chatDao.pruneChatsGoneRemote({'alive'});

      expect(pruned, 1);
      expect(await chatDao.getById('ghost'), isNull);
      expect(await chatDao.getById('alive'), isNotNull);
      expect(await chatDao.getById('pending'), isNotNull);
      expect(
        (await chatDao.getTombstonedChats()).map((c) => c.id),
        contains('tomb'),
      );
    });

    test('empty local table prunes nothing', () async {
      expect(await chatDao.pruneChatsGoneRemote({'any'}), 0);
      expect(await chatDao.pruneChatsGoneRemote({}), 0);
    });
  });
}
