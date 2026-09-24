import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/local_chat_dao.dart';
import 'package:aiproject/data/local/local_message_dao.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/data/models/chat_session_model.dart';
import 'package:aiproject/services/sync/sync_service.dart';

// Phase 3 sync-engine regression suite: locks the Phase 1+2 semantics the
// SyncService worker depends on (tombstones, preserving replace, batched
// pagination, H6 failure retention, no-uid skip).
//
// Scope: `SyncService` exposes additive `@visibleForTesting` seams for its
// hard-wired dependencies (DAO singletons, `Supabase*Service` statics,
// `AuthService.currentUser`) that default to the real singletons/statics,
// so production behavior is identical. Groups (a)–(h) below prove the
// DAO-level contracts the worker relies on against a real in-memory
// database (`DatabaseHelper.testDatabase`), plus the public no-uid
// behaviour of `SyncService` itself (`flushPending` no-op, pending
// counters, migration passthrough). Group (i) drives the remote halves end
// to end through those seams with a fake remote (`FakeSyncRemote`):
// flush push (success + H6 failure retention), tombstone delete sync,
// paged refresh fetches with the `chatsFetched` guard, and tombstone+ghost
// composition through a full flush+refresh cycle. The pending-signup path
// (`LocalUserDao`/`SessionManager`) has no seam and stays covered by the
// no-uid skip test. `docs/sync.md` documents the worker contract.

ChatSessionModel syncChat({
  String id = 'c1',
  String userId = 'u1',
  String title = 't',
  bool isSynced = false,
  bool isDeleted = false,
  int unread = 0,
}) {
  return ChatSessionModel(
    id: id,
    userId: userId,
    title: title,
    lastMessage: 'm',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    unread: unread,
    isSynced: isSynced,
    isDeleted: isDeleted,
  );
}

ChatMessageModel syncMessage({
  String id = 'm1',
  String chatId = 'c1',
  String text = 'hello',
  bool isSynced = false,
  bool isDeleted = false,
}) {
  return ChatMessageModel(
    id: id,
    chatId: chatId,
    text: text,
    isUser: true,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    isSynced: isSynced,
    isDeleted: isDeleted,
  );
}

/// Mirrors the upstream-queue filter in `SyncService._flushPending`:
/// only tombstones still marked unsynced are pushed remotely.
List<ChatSessionModel> pendingDeleteQueue(
  List<ChatSessionModel> tombstones,
) {
  return tombstones.where((chat) => !chat.isSynced).toList();
}

/// Mirrors the downstream-prune loop in
/// `SyncService._refreshLocalCacheFromRemote`: drops tombstones whose ids
/// are absent from the fetched remote set; no-ops when the fetch failed
/// (`chatsFetched == false`) so an offline failure never looks like
/// "remote deleted everything".
Future<int> pruneTombstonesGoneRemote(
  Set<String> remoteChatIds, {
  required bool chatsFetched,
}) async {
  if (!chatsFetched) return 0;
  final chatDao = LocalChatDao.instance;
  final msgDao = LocalMessageDao.instance;
  final tombstones = await chatDao.getTombstonedChats();
  var pruned = 0;
  for (final tombstone in tombstones) {
    if (remoteChatIds.contains(tombstone.id)) continue;
    await msgDao.hardDeleteByChat(tombstone.id);
    await chatDao.hardDelete(tombstone.id);
    pruned++;
  }
  return pruned;
}

/// Mirrors the ghost-chat prune step in
/// `SyncService._refreshLocalCacheFromRemote`: delegates to the DAO
/// primitive `LocalChatDao.pruneChatsGoneRemote` behind the same
/// `chatsFetched` guard, so a failed fetch never prunes. Ghosts are
/// disjoint from tombstones (`is_synced = 1, is_deleted = 0` only), so this
/// runs after [pruneTombstonesGoneRemote] in production without overlap.
Future<int> pruneGhostsGoneRemote(
  Set<String> remoteChatIds, {
  required bool chatsFetched,
}) async {
  if (!chatsFetched) return 0;
  return LocalChatDao.instance.pruneChatsGoneRemote(remoteChatIds);
}

/// In-memory fake for the `Supabase*Service` statics behind the
/// `SyncService` `@visibleForTesting` seams. The `fail*` flags simulate
/// remote failure; a generic [Exception] is non-retryable
/// (`AuthRetryPolicy`), so the worker's H6 path runs without backoff
/// delays.
class FakeSyncRemote {
  final pushedChats = <String, ChatSessionModel>{};
  final pushedMessages = <String, ChatMessageModel>{};
  final deletedChatIds = <String>[];
  List<ChatSessionModel> chatsToServe = [];
  List<ChatMessageModel> messagesToServe = [];
  int getChatsPagedCalls = 0;
  int getAllMessagesPagedCalls = 0;
  bool failSaves = false;
  bool failDeletes = false;
  bool failLists = false;
}

/// Wires [fake] into a `SyncService` via the `@visibleForTesting` seams.
/// Defaults the uid to 'u1' — tests never touch `AuthService.currentUser`.
SyncService syncWithFakeRemote(FakeSyncRemote fake, {String uid = 'u1'}) {
  final sync = SyncService(ConnectivityService.instance);
  sync.currentUserIdOverrideForTest = () => uid;
  sync.saveChatOverrideForTest = (u, chat) async {
    if (fake.failSaves) throw Exception('fake saveChat failure');
    fake.pushedChats[chat.id] = chat;
  };
  sync.saveMessageOverrideForTest = (u, chatId, msg) async {
    if (fake.failSaves) throw Exception('fake saveMessage failure');
    fake.pushedMessages[msg.id] = msg;
  };
  sync.deleteChatOverrideForTest = (u, chatId) async {
    if (fake.failDeletes) throw Exception('fake deleteChat failure');
    fake.deletedChatIds.add(chatId);
  };
  sync.getChatsPagedOverrideForTest = (u) async {
    fake.getChatsPagedCalls++;
    if (fake.failLists) throw Exception('fake getChatsPaged failure');
    return fake.chatsToServe;
  };
  sync.getAllMessagesPagedOverrideForTest = (u) async {
    fake.getAllMessagesPagedCalls++;
    if (fake.failLists) throw Exception('fake getAllMessagesPaged failure');
    return fake.messagesToServe;
  };
  return sync;
}

Future<void> createSyncSchema(Database db) async {
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
  await db.execute('''
    CREATE TABLE pending_signups (
      local_id TEXT PRIMARY KEY,
      email TEXT NOT NULL,
      password TEXT NOT NULL,
      display_name TEXT NOT NULL,
      recovery_code TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      is_synced INTEGER DEFAULT 0,
      provider TEXT DEFAULT 'password',
      password_salt TEXT DEFAULT ''
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
        onCreate: (db, version) async => createSyncSchema(db),
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
    await db.delete('pending_signups');
  });

  group('(a) tombstone lifecycle — offline delete never reappears', () {
    test('refresh with same id keeps the tombstone, hides it from lists',
        () async {
      await chatDao.insert(
        syncChat(id: 'c1', isSynced: false, isDeleted: true),
      );

      // Remote still holds the old row; the preserving replace must skip it.
      await chatDao.replaceChatsPreservingUnsynced(
        [syncChat(id: 'c1', isSynced: true)],
      );

      final kept = await chatDao.getById('c1');
      expect(kept, isNotNull);
      expect(kept!.isDeleted, true);
      expect(kept.isSynced, false);
      expect(await chatDao.getByUserId('u1'), isEmpty);
      expect(
        (await chatDao.getTombstonedChats()).map((c) => c.id),
        contains('c1'),
      );
    });

    test('message tombstones survive a preserving message refresh', () async {
      await chatDao.insert(syncChat(id: 'c1', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'm1', chatId: 'c1', isSynced: true),
      );
      await db.update(
        'messages',
        {'is_deleted': 1, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: ['m1'],
      );

      await msgDao.replaceMessagesPreservingUnsynced(
        [syncMessage(id: 'm1', chatId: 'c1', isSynced: true)],
      );

      final rows = await db.query('messages', where: 'id = ?', whereArgs: ['m1']);
      expect(rows.single['is_deleted'], 1);
      expect(await msgDao.getByChat('c1'), isEmpty);
    });
  });

  group('(b) upstream queue — offline delete pushed on next flush', () {
    test('only unsynced tombstones are queued for remote delete', () async {
      await chatDao.insert(
        syncChat(id: 'pending', isSynced: false, isDeleted: true),
      );
      await chatDao.insert(
        syncChat(id: 'already-pushed', isSynced: true, isDeleted: true),
      );

      final queue = pendingDeleteQueue(await chatDao.getTombstonedChats());
      expect(queue.map((c) => c.id), contains('pending'));
      expect(queue.map((c) => c.id), isNot(contains('already-pushed')));
    });

    test('successful push hard-deletes the chat and its messages', () async {
      await chatDao.insert(
        syncChat(id: 'gone', isSynced: false, isDeleted: true),
      );
      await msgDao.insert(syncMessage(id: 'm1', chatId: 'gone'));
      await msgDao.insert(syncMessage(id: 'm2', chatId: 'gone'));

      // Local half of the post-push step in `SyncService._flushPending`.
      await msgDao.hardDeleteByChat('gone');
      await chatDao.hardDelete('gone');

      expect(await chatDao.getById('gone'), isNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ?', whereArgs: ['gone']),
        isEmpty,
      );
      expect(await chatDao.getTombstonedChats(), isEmpty);
    });
  });

  group('(c) downstream prune — remote-gone tombstones finish locally', () {
    test('tombstone absent remotely is pruned with its messages', () async {
      await chatDao.insert(
        syncChat(id: 'dead', isSynced: false, isDeleted: true),
      );
      await msgDao.insert(syncMessage(id: 'm1', chatId: 'dead'));

      final pruned = await pruneTombstonesGoneRemote(
        {'other-chat'},
        chatsFetched: true,
      );

      expect(pruned, 1);
      expect(await chatDao.getById('dead'), isNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ?', whereArgs: ['dead']),
        isEmpty,
      );
    });

    test('tombstone still present remotely is kept for the next push',
        () async {
      await chatDao.insert(
        syncChat(id: 'keep', isSynced: false, isDeleted: true),
      );

      final pruned = await pruneTombstonesGoneRemote(
        {'keep'},
        chatsFetched: true,
      );

      expect(pruned, 0);
      expect(
        (await chatDao.getTombstonedChats()).map((c) => c.id),
        contains('keep'),
      );
    });

    test('chatsFetched guard: failed fetch never prunes', () async {
      await chatDao.insert(
        syncChat(id: 'guarded', isSynced: false, isDeleted: true),
      );

      final pruned = await pruneTombstonesGoneRemote(
        {},
        chatsFetched: false,
      );

      expect(pruned, 0);
      expect(await chatDao.getById('guarded'), isNotNull);
    });
  });

  group('(d) unsynced-preserve ordering — flush before refresh', () {
    test('local unsynced edit survives refresh, then remote applies', () async {
      await chatDao.insert(
        syncChat(id: 'c1', title: 'local edit', isSynced: false),
      );

      // Refresh first: unsynced row must win.
      await chatDao.replaceChatsPreservingUnsynced(
        [syncChat(id: 'c1', title: 'remote title', isSynced: true)],
      );
      expect((await chatDao.getById('c1'))!.title, 'local edit');

      // Simulated flush marks the row synced; the next refresh applies.
      await chatDao.update(syncChat(id: 'c1', title: 'local edit', isSynced: true));
      await chatDao.replaceChatsPreservingUnsynced(
        [syncChat(id: 'c1', title: 'remote title', isSynced: true)],
      );
      final applied = (await chatDao.getById('c1'))!;
      expect(applied.title, 'remote title');
      expect(applied.isSynced, true);
    });

    test('synced rows refresh while unsynced messages are preserved',
        () async {
      await chatDao.insert(syncChat(id: 'c1', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'local-only', chatId: 'c1', isSynced: false),
      );

      await msgDao.replaceMessagesPreservingUnsynced([
        syncMessage(id: 'local-only', chatId: 'c1', text: 'remote', isSynced: true),
        syncMessage(id: 'remote-new', chatId: 'c1', text: 'new', isSynced: true),
      ]);

      final rows = await msgDao.getByChat('c1');
      expect(rows.map((m) => m.id), contains('remote-new'));
      final keptLocal = await db.query('messages',
          where: 'id = ?', whereArgs: ['local-only']);
      expect(keptLocal.single['text'], 'hello');
      expect(keptLocal.single['is_synced'], 0);
    });
  });

  group('(e) pagination over 1,000+ rows', () {
    test('inclusive range windows tile without gaps or overlaps', () {
      const pageSize = 500;
      int from(int page) => page * pageSize;
      int to(int page) => from(page) + pageSize - 1;

      // Three pages cover 1,200 rows: [0..499], [500..999], [1000..1499]
      // with the third page short (200 rows) terminating the loop.
      expect(from(0), 0);
      expect(to(0), 499);
      expect(from(1), to(0) + 1);
      expect(to(1), 999);
      expect(from(2), to(1) + 1);
      expect(to(2), 1499);
      expect(200 < pageSize, true);
      expect(500.clamp(1, 1000), 500);
    });

    test('preserving chat replace handles a 1,200-row remote batch',
        () async {
      final remote = List.generate(
        1200,
        (i) => syncChat(id: 'bulk-$i', isSynced: true),
      );
      await chatDao.replaceChatsPreservingUnsynced(remote);

      final countRow =
          await db.rawQuery('SELECT COUNT(*) AS n FROM chat_sessions');
      expect(countRow.single['n'], 1200);
    });

    test('preserving message replace handles a multi-chunk batch', () async {
      await chatDao.insert(syncChat(id: 'c1', isSynced: true));
      final remote = List.generate(
        600,
        (i) => syncMessage(id: 'bulk-m-$i', chatId: 'c1', isSynced: true),
      );
      await msgDao.replaceMessagesPreservingUnsynced(remote);

      final countRow = await db
          .rawQuery('SELECT COUNT(*) AS n FROM messages WHERE chat_id = ?', ['c1']);
      expect(countRow.single['n'], 600);
    });
  });

  group('(f) H6 — failed remote push keeps rows pending', () {
    test('failed delete push keeps the tombstone queued', () async {
      await chatDao.insert(
        syncChat(id: 'retry-me', isSynced: false, isDeleted: true),
      );

      // Failure path in `_flushPending` skips the hard delete entirely.
      final queue = pendingDeleteQueue(await chatDao.getTombstonedChats());
      expect(queue.map((c) => c.id), contains('retry-me'));
      expect((await chatDao.getById('retry-me'))!.isSynced, false);
    });

    test('failed message push keeps is_synced=0', () async {
      await chatDao.insert(syncChat(id: 'c1', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'unsent', chatId: 'c1', isSynced: false),
      );

      // Failure path never calls update(isSynced: true).
      expect(
        (await msgDao.getUnsynced()).map((m) => m.id),
        contains('unsent'),
      );
    });

    test('tombstones are excluded from the unsynced-edit list', () async {
      await chatDao.insert(
        syncChat(id: 't1', isSynced: false, isDeleted: true),
      );
      await chatDao.insert(
        syncChat(id: 'e1', title: 'edit', isSynced: false, isDeleted: false),
      );

      expect(
        (await chatDao.getUnsynced()).map((c) => c.id),
        contains('e1'),
      );
      expect(
        (await chatDao.getUnsynced()).map((c) => c.id),
        isNot(contains('t1')),
      );
    });
  });

  group('(g) no-uid skip — SyncService public behaviour offline', () {
    test('flushPending without a uid leaves local rows untouched', () async {
      final sync = SyncService(ConnectivityService.instance);
      await chatDao.insert(
        syncChat(id: 'local', title: 'local', isSynced: false),
      );
      await chatDao.insert(
        syncChat(id: 'tomb', isSynced: false, isDeleted: true),
      );

      // No backend session in tests, so `AuthService.currentUser` is null
      // and the flush must no-op instead of throwing.
      await sync.flushPending();

      expect((await chatDao.getById('local'))!.isSynced, false);
      expect((await chatDao.getById('tomb'))!.isDeleted, true);
      sync.dispose();
    });

    test('pending counters report unsynced chats and messages', () async {
      final sync = SyncService(ConnectivityService.instance);
      await chatDao.insert(syncChat(id: 'c1', isSynced: false));
      await msgDao.insert(syncMessage(id: 'm1', chatId: 'c1', isSynced: false));

      expect(await sync.getPendingCount(), greaterThanOrEqualTo(2));
      final breakdown = await sync.getPendingBreakdown();
      expect(breakdown['chats'], greaterThanOrEqualTo(1));
      expect(breakdown['messages'], greaterThanOrEqualTo(1));
      expect(breakdown['users'], equals(0));
      sync.dispose();
    });

    test('migrateOfflineUserChats re-homes chats without crashing', () async {
      final sync = SyncService(ConnectivityService.instance);
      await chatDao.insert(
        syncChat(id: 'c1', userId: 'old-uid', isSynced: true),
      );

      await sync.migrateOfflineUserChats('old-uid', 'new-uid');

      expect((await chatDao.getById('c1'))!.userId, 'new-uid');
      // Messages carry no user_id column; the schema-aware no-op must hold.
      await msgDao.migrateUserId('old-uid', 'new-uid');
      sync.dispose();
    });
  });

  group('(h) ghost-chat prune — synced rows gone remotely without tombstone',
      () {
    test('ghost absent remotely is pruned with its messages', () async {
      await chatDao.insert(syncChat(id: 'ghost', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'm1', chatId: 'ghost', isSynced: true),
      );

      final pruned = await pruneGhostsGoneRemote(
        {'other-chat'},
        chatsFetched: true,
      );

      expect(pruned, 1);
      expect(await chatDao.getById('ghost'), isNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ?', whereArgs: ['ghost']),
        isEmpty,
      );
    });

    test('ghost still present remotely is kept', () async {
      await chatDao.insert(syncChat(id: 'alive', isSynced: true));

      final pruned = await pruneGhostsGoneRemote(
        {'alive'},
        chatsFetched: true,
      );

      expect(pruned, 0);
      expect(await chatDao.getById('alive'), isNotNull);
    });

    test('unsynced rows and tombstones are never ghost-pruned', () async {
      await chatDao.insert(
        syncChat(id: 'pending', isSynced: false),
      );
      await chatDao.insert(
        syncChat(id: 'tomb', isSynced: true, isDeleted: true),
      );
      // Synced chat holding an unsynced message: pending local work wins.
      await chatDao.insert(syncChat(id: 'busy', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'unsent', chatId: 'busy', isSynced: false),
      );

      final pruned = await pruneGhostsGoneRemote(
        {'other-chat'},
        chatsFetched: true,
      );

      expect(pruned, 0);
      expect(await chatDao.getById('pending'), isNotNull);
      expect(await chatDao.getById('busy'), isNotNull);
      expect(
        (await chatDao.getTombstonedChats()).map((c) => c.id),
        contains('tomb'),
      );
    });

    test('chatsFetched guard: failed fetch never ghost-prunes', () async {
      await chatDao.insert(syncChat(id: 'ghost', isSynced: true));

      final pruned = await pruneGhostsGoneRemote(
        {},
        chatsFetched: false,
      );

      expect(pruned, 0);
      expect(await chatDao.getById('ghost'), isNotNull);
    });

    test('tombstone + ghost loops compose without overlap', () async {
      await chatDao.insert(
        syncChat(id: 'dead', isSynced: false, isDeleted: true),
      );
      await chatDao.insert(syncChat(id: 'ghost', isSynced: true));
      await chatDao.insert(syncChat(id: 'alive', isSynced: true));

      // Production order: tombstones first, then ghosts.
      final tombstonesPruned = await pruneTombstonesGoneRemote(
        {'alive', 'ghost'},
        chatsFetched: true,
      );
      final ghostsPruned = await pruneGhostsGoneRemote(
        {'alive'},
        chatsFetched: true,
      );

      expect(tombstonesPruned, 1);
      expect(ghostsPruned, 1);
      expect(await chatDao.getById('dead'), isNull);
      expect(await chatDao.getById('ghost'), isNull);
      expect(await chatDao.getById('alive'), isNotNull);
    });

    test('end-to-end ghost regression: c1 pruned with messages, c2 + c3 survive',
        () async {
      // c1: synced ghost absent remotely (+ synced message to prove cascade).
      await chatDao.insert(syncChat(id: 'c1', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'm-c1', chatId: 'c1', isSynced: true),
      );
      // c2: unsynced local-only row — never pruned even when listed remotely.
      await chatDao.insert(syncChat(id: 'c2', isSynced: false));
      // c3: synced row still present remotely (+ message that must survive).
      await chatDao.insert(syncChat(id: 'c3', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'm-c3', chatId: 'c3', isSynced: true),
      );

      final pruned = await pruneGhostsGoneRemote(
        {'c2', 'c3'},
        chatsFetched: true,
      );

      expect(pruned, 1);
      expect(await chatDao.getById('c1'), isNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ?', whereArgs: ['c1']),
        isEmpty,
      );
      expect(await chatDao.getById('c2'), isNotNull);
      expect(await chatDao.getById('c3'), isNotNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ? AND id = ?', whereArgs: ['c3', 'm-c3']),
        hasLength(1),
      );
    });
  });

  group('(i) remote halves via SyncService seams — flush+refresh fakes', () {
    test('(a) flush success pushes unsynced rows and marks them synced',
        () async {
      await chatDao.insert(syncChat(id: 'c1', isSynced: false));
      await msgDao.insert(
        syncMessage(id: 'm1', chatId: 'c1', isSynced: false),
      );

      final fake = FakeSyncRemote();
      final sync = syncWithFakeRemote(fake);

      await sync.flushPending();

      expect(fake.pushedChats.keys, contains('c1'));
      expect(fake.pushedMessages.keys, contains('m1'));
      expect((await chatDao.getById('c1'))!.isSynced, true);
      final msgRows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['m1'],
      );
      expect(msgRows.single['is_synced'], 1);
      sync.dispose();
    });

    test('(b) flush failure keeps is_synced=0 for chats+messages (H6)',
        () async {
      await chatDao.insert(syncChat(id: 'c1', isSynced: false));
      await msgDao.insert(
        syncMessage(id: 'm1', chatId: 'c1', isSynced: false),
      );

      final fake = FakeSyncRemote()..failSaves = true;
      final sync = syncWithFakeRemote(fake);

      await sync.flushPending();

      expect(fake.pushedChats, isEmpty);
      expect(fake.pushedMessages, isEmpty);
      expect((await chatDao.getById('c1'))!.isSynced, false);
      expect(
        (await msgDao.getUnsynced()).map((m) => m.id),
        contains('m1'),
      );
      sync.dispose();
    });

    test('(c) tombstone delete is pushed remotely then hard-deleted locally',
        () async {
      await chatDao.insert(
        syncChat(id: 'dead', isSynced: false, isDeleted: true),
      );
      await msgDao.insert(
        syncMessage(id: 'm1', chatId: 'dead', isSynced: true),
      );

      final fake = FakeSyncRemote();
      final sync = syncWithFakeRemote(fake);

      await sync.flushPending();

      expect(fake.deletedChatIds, contains('dead'));
      expect(await chatDao.getById('dead'), isNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ?', whereArgs: ['dead']),
        isEmpty,
      );
      sync.dispose();
    });

    test('(c) failed delete keeps the tombstone queued (H6)', () async {
      await chatDao.insert(
        syncChat(id: 'retry', isSynced: false, isDeleted: true),
      );

      final fake = FakeSyncRemote()..failDeletes = true;
      final sync = syncWithFakeRemote(fake);

      await sync.flushPending();

      expect(fake.deletedChatIds, isEmpty);
      final kept = await chatDao.getById('retry');
      expect(kept, isNotNull);
      expect(kept!.isSynced, false);
      expect(kept.isDeleted, true);
      sync.dispose();
    });

    test('(d) refresh drives the paged fetches, preserves local edits',
        () async {
      await chatDao.insert(
        syncChat(id: 'local', title: 'local edit', isSynced: false),
      );

      final fake = FakeSyncRemote()
        ..chatsToServe = [
          syncChat(id: 'local', title: 'remote title', isSynced: true),
          syncChat(id: 'remote-new', title: 'new', isSynced: true),
        ]
        ..messagesToServe = [
          syncMessage(
            id: 'rm1',
            chatId: 'remote-new',
            text: 'new',
            isSynced: true,
          ),
        ];
      final sync = syncWithFakeRemote(fake);

      await sync.refreshLocalCacheForTest();

      expect(fake.getChatsPagedCalls, greaterThanOrEqualTo(1));
      expect(fake.getAllMessagesPagedCalls, greaterThanOrEqualTo(1));
      // Unsynced local edit wins over the served remote row (flush first).
      expect((await chatDao.getById('local'))!.title, 'local edit');
      expect(await chatDao.getById('remote-new'), isNotNull);
      expect(
        (await msgDao.getByChat('remote-new')).map((m) => m.id),
        contains('rm1'),
      );
      sync.dispose();
    });

    test('(d) failed remote list never prunes (chatsFetched guard)',
        () async {
      await chatDao.insert(syncChat(id: 'ghost', isSynced: true));

      final fake = FakeSyncRemote()..failLists = true;
      final sync = syncWithFakeRemote(fake);

      // Must not throw and must not prune: an offline failure never looks
      // like "remote deleted everything".
      await sync.refreshLocalCacheForTest();

      expect(await chatDao.getById('ghost'), isNotNull);
      sync.dispose();
    });

    test('(e) full refresh composes tombstone + ghost prune', () async {
      await chatDao.insert(
        syncChat(id: 'dead', isSynced: false, isDeleted: true),
      );
      await chatDao.insert(syncChat(id: 'ghost', isSynced: true));
      await msgDao.insert(
        syncMessage(id: 'm-ghost', chatId: 'ghost', isSynced: true),
      );
      await chatDao.insert(syncChat(id: 'alive', isSynced: true));

      final fake = FakeSyncRemote()
        ..chatsToServe = [syncChat(id: 'alive', isSynced: true)];
      final sync = syncWithFakeRemote(fake);

      await sync.refreshLocalCacheForTest();

      expect(await chatDao.getById('dead'), isNull);
      expect(await chatDao.getById('ghost'), isNull);
      expect(
        await db.query('messages',
            where: 'chat_id = ?', whereArgs: ['ghost']),
        isEmpty,
      );
      expect(await chatDao.getById('alive'), isNotNull);
      sync.dispose();
    });

    test('(e) flush+refresh end to end: delete pushed, ghost pruned',
        () async {
      await chatDao.insert(
        syncChat(id: 'dead', isSynced: false, isDeleted: true),
      );
      await chatDao.insert(syncChat(id: 'ghost', isSynced: true));
      await chatDao.insert(syncChat(id: 'alive', isSynced: true));

      final fake = FakeSyncRemote()
        ..chatsToServe = [syncChat(id: 'alive', isSynced: true)];
      final sync = syncWithFakeRemote(fake);

      await sync.flushPending();
      expect(fake.deletedChatIds, contains('dead'));
      expect(await chatDao.getById('dead'), isNull);

      await sync.refreshLocalCacheForTest();
      expect(await chatDao.getById('ghost'), isNull);
      expect(await chatDao.getById('alive'), isNotNull);
      sync.dispose();
    });
  });
}
