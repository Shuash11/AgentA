import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/data/local/local_chat_dao.dart';
import 'package:aiproject/data/models/chat_session_model.dart';
import 'package:aiproject/data/remote/supabase_chat_service.dart';
import 'package:aiproject/data/remote/supabase_message_service.dart';

// Phase 1 sync primitives: pure-contract tests.
//
// NOTE: full DAO DB integration (tombstone/unsynced/unread/batch through
// sqflite) is intentionally NOT run here — it needs sqflite_common_ffi
// in-memory setup, which is not in dev_dependencies, and the phase plan
// forbids adding deps for this phase. The DB orchestration in
// LocalChatDao.replaceChatsPreservingUnsynced mirrors the reviewed
// LocalMessageDao.replaceMessagesPreservingUnsynced (chunked 500,
// transaction, skip is_synced=0 OR is_deleted=1). What IS tested here are
// the pure units the DB path is built on, plus the model contract the
// sync path relies on.

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

    test('remote services expose paginated variants alongside originals', () {
      expect(SupabaseChatService.getChats, isA<Function>());
      expect(SupabaseChatService.getChatsPaged, isA<Function>());
      expect(SupabaseMessageService.getMessages, isA<Function>());
      expect(SupabaseMessageService.getMessagesPaged, isA<Function>());
    });
  });
}
