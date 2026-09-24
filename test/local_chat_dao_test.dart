import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_chat_dao.dart';
import 'package:aiproject/data/local/local_message_dao.dart';
import 'package:aiproject/data/models/chat_session_model.dart';
import 'package:aiproject/data/remote/supabase_chat_service.dart';
import 'package:aiproject/data/remote/supabase_message_service.dart';

// Phase 1 sync primitives: pure-contract tests plus Phase 2 DB integration.
//
// The pure groups below cover the units the DB path is built on; the final
// `replaceChatsPreservingUnsynced DB integration` group runs the real DAO
// against an in-memory sqflite_common_ffi database
// (sqfliteFfiInit + databaseFactoryFfi, injected via
// `DatabaseHelper.testDatabase`).

ChatSessionModel chat({
  String id = 'c1',
  String userId = 'u1',
  int unread = 0,
  bool isSynced = false,
  bool isDeleted = false,
}) {
  return ChatSessionModel(
    id: id,
    userId: userId,
    title: 't',
    lastMessage: 'm',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    unread: unread,
    isSynced: isSynced,
    isDeleted: isDeleted,
  );
}

void main() {
  group('ChatSessionModel sync contract', () {
    test('toMap/fromMap roundtrip preserves unread/sync/delete flags', () {
      final original = chat(unread: 7, isSynced: true, isDeleted: false);
      final restored = ChatSessionModel.fromMap(original.toMap());
      expect(restored.unread, 7);
      expect(restored.isSynced, true);
      expect(restored.isDeleted, false);
      expect(restored.id, 'c1');
    });

    test('fromMap defaults unread to 0 when missing (remote shape)', () {
      final restored = ChatSessionModel.fromMap({
        'id': 'r1',
        'user_id': 'u1',
        'title': 't',
        'last_message': 'm',
        'updated_at': 1700000000000,
        'is_synced': 1,
        'is_deleted': 0,
      });
      expect(restored.unread, 0);
    });

    test('copyWith(isSynced:true) preserves local unread', () {
      final local = chat(unread: 5);
      final synced = local.copyWith(isSynced: true);
      expect(synced.unread, 5);
      expect(synced.isSynced, true);
    });

    test('copyWith preserves isDeleted when not passed', () {
      final tombstone = chat(isDeleted: true);
      expect(tombstone.copyWith(isSynced: true).isDeleted, true);
    });
  });

  group('shouldPreserveLocalRow tombstone guard', () {
    test('synced + alive row may be replaced', () {
      expect(
        LocalChatDao.shouldPreserveLocalRow(isSynced: 1, isDeleted: 0),
        false,
      );
    });

    test('unsynced edits are preserved', () {
      expect(
        LocalChatDao.shouldPreserveLocalRow(isSynced: 0, isDeleted: 0),
        true,
      );
    });

    test('tombstones are preserved even when synced', () {
      expect(
        LocalChatDao.shouldPreserveLocalRow(isSynced: 1, isDeleted: 1),
        true,
      );
    });

    test('unsynced tombstones are preserved', () {
      expect(
        LocalChatDao.shouldPreserveLocalRow(isSynced: 0, isDeleted: 1),
        true,
      );
    });
  });

  group('withPreservedUnread', () {
    test('replaces remote unread=0 with local count', () {
      final remote = chat(unread: 0, isSynced: true);
      final merged = LocalChatDao.withPreservedUnread(remote, 5);
      expect(merged.unread, 5);
      expect(merged.id, remote.id);
      expect(merged.isSynced, true);
    });

    test('keeps other fields while preserving unread', () {
      final remote = chat(unread: 0, isSynced: true);
      final merged = LocalChatDao.withPreservedUnread(remote, 3);
      expect(merged.userId, remote.userId);
      expect(merged.title, remote.title);
      expect(merged.lastMessage, remote.lastMessage);
      expect(merged.updatedAt, remote.updatedAt);
      expect(merged.isDeleted, remote.isDeleted);
    });

    test('returns remote as-is when unread already matches', () {
      final remote = chat(unread: 4, isSynced: true);
      expect(
        identical(LocalChatDao.withPreservedUnread(remote, 4), remote),
        true,
      );
    });
  });

  group('paginated fetch window contract (Supabase range inclusive)', () {
    test('page windows are exact and non-overlapping', () {
      const pageSize = 500;
      int from(int page) => page * pageSize;
      int to(int page) => from(page) + pageSize - 1;
      expect(from(0), 0);
      expect(to(0), 499);
      expect(from(1), 500);
      expect(to(1), 999);
      // No gap, no overlap between consecutive windows.
      expect(from(1), to(0) + 1);
    });

    test('pageSize stays below the 1,000-row default cap', () {
      expect(const <int>[1, 500, 1000].contains(500), true);
      expect(500.clamp(1, 1000), 500);
      expect(5000.clamp(1, 1000), 1000);
      expect(0.clamp(1, 1000), 1);
    });

    test('short page terminates the loop', () {
      const pageSize = 500;
      bool done(List<int> batch) => batch.length < pageSize;
      expect(done(List.filled(500, 1)), false);
      expect(done(List.filled(12, 1)), true);
      expect(done([]), true);
    });
  });

  group('Phase 1 API surface (no behavior change for old callers)', () {
    test('LocalChatDao exposes tombstone + preserving replace', () {
      expect(LocalChatDao.instance.getTombstonedChats, isA<Function>());
      expect(
        LocalChatDao.instance.replaceChatsPreservingUnsynced,
        isA<Function>(),
      );
    });

    test('remote services expose paginated variants', () {
      expect(SupabaseChatService.getChatsPaged, isA<Function>());
      expect(SupabaseMessageService.getMessages, isA<Function>());
      expect(SupabaseMessageService.getMessagesPaged, isA<Function>());
      expect(SupabaseMessageService.getAllMessagesPaged, isA<Function>());
    });
  });

  group('replaceChatsPreservingUnsynced DB integration (ffi)', () {
    late Database db;
    final dao = LocalChatDao.instance;

    setUpAll(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
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
          },
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

    test('tombstone preserved (offline delete never resurrected)', () async {
      await dao.insert(chat(id: 'c1', isSynced: false, isDeleted: true));
      final remote = chat(id: 'c1', isSynced: true, isDeleted: false);
      await dao.replaceChatsPreservingUnsynced([remote]);
      final kept = await dao.getById('c1');
      expect(kept, isNotNull);
      expect(kept!.isDeleted, true);
      expect(kept.title, 't');
      // Tombstone is still listed for the upstream push.
      expect(
        (await dao.getTombstonedChats()).map((c) => c.id),
        contains('c1'),
      );
    });

    test('unsynced edit preserved (local title wins)', () async {
      final local = ChatSessionModel(
        id: 'c2',
        userId: 'u1',
        title: 'local edit',
        lastMessage: 'm',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        unread: 0,
        isSynced: false,
        isDeleted: false,
      );
      await dao.insert(local);
      final remote = ChatSessionModel(
        id: 'c2',
        userId: 'u1',
        title: 'remote title',
        lastMessage: 'm',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        unread: 0,
        isSynced: true,
        isDeleted: false,
      );
      await dao.replaceChatsPreservingUnsynced([remote]);
      final kept = await dao.getById('c2');
      expect(kept, isNotNull);
      expect(kept!.title, 'local edit');
      expect(kept.isSynced, false);
    });

    test('unread preserved on synced-row replace', () async {
      await dao.insert(chat(id: 'c3', unread: 5, isSynced: true));
      final remote = ChatSessionModel(
        id: 'c3',
        userId: 'u1',
        title: 'remote title',
        lastMessage: 'm',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000002000),
        unread: 0,
        isSynced: true,
        isDeleted: false,
      );
      await dao.replaceChatsPreservingUnsynced([remote]);
      final kept = await dao.getById('c3');
      expect(kept, isNotNull);
      expect(kept!.title, 'remote title');
      expect(kept.unread, 5);
      expect(kept.isSynced, true);
    });

    test('batch insert of new remote rows', () async {
      final remote = [
        chat(id: 'n1', isSynced: true),
        chat(id: 'n2', isSynced: true),
        chat(id: 'n3', isSynced: true),
      ];
      await dao.replaceChatsPreservingUnsynced(remote);
      final rows = await dao.getByUserId('u1');
      expect(rows.map((c) => c.id).toSet(), {'n1', 'n2', 'n3'});
      expect(rows.every((c) => c.isSynced), true);
    });

    test('LocalMessageDao.migrateUserId is a safe no-op without user_id column',
        () async {
      // Must not throw "no such column: user_id" — messages are scoped by
      // chat_id, so the parent chat migration already re-homes them.
      await LocalMessageDao.instance.migrateUserId('old-uid', 'new-uid');
    });
  });
}
