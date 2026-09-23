# Sync engine semantics

Offline-first chat sync: local SQLite is the source of truth while offline;
`SyncService` reconciles with the remote database when connectivity returns.
Related: `docs/backend-rls.md` (server-side ownership policies).

## Tombstone lifecycle

Deletes are never applied directly to the remote while offline. Instead each
delete moves through three stages:

1. `markDeleted` — the local row is flagged `is_deleted = 1, is_synced = 0`
   (chats via `LocalChatDao.markDeleted`, messages via
   `LocalMessageDao.markDeletedByChat`). The row stays in the local database
   so the intent survives app restarts. List queries filter tombstones out
   (`getByUserId` / `getByChat` require `is_deleted = 0`), and the
   unsynced-edit queries exclude them (`is_synced = 0 AND is_deleted = 0`).
2. Flush push — on the next online pass `_flushPending` reads
   `getTombstonedChats()`, keeps only rows still marked unsynced
   (`where((chat) => !chat.isSynced)`), deletes each one remotely
   (`SupabaseChatService.deleteChat`), then hard-deletes locally
   (`hardDeleteByChat` + `hardDelete`).
3. Hard delete — after a successful push the local rows are gone entirely;
   there is nothing left to resurrect.

Failure retention (H6): any exception during the push skips the hard delete,
so the tombstone stays queued (`is_synced = 0`) for the next pass. Rows are
only ever marked synced after a confirmed remote write — never optimistically.

## Batched refresh

`_refreshLocalCacheFromRemote` performs one paginated fetch per table, then
one batch replace per table (no per-chat round trips):

- Chats: `SupabaseChatService.getChatsPaged(uid)` → mark `isSynced: true` →
  `replaceChatsPreservingUnsynced`.
- Messages: `SupabaseMessageService.getAllMessagesPaged(uid)` → mark
  `isSynced: true` → `replaceMessagesPreservingUnsynced`.

Pagination: page size defaults to 500 (clamped to 1–1000, below the remote
default 1,000-row cap). Windows use inclusive `.range(from, to)` with
`to = from + pageSize - 1`; a short page (`length < pageSize`) terminates
the loop. Ordering is `updated_at` + `id` tiebreaker for chats and
`timestamp` + `id` tiebreaker for messages, so equal-timestamp rows page
deterministically.

Preserving replace: before inserting, the DAO probes local rows in 500-id
chunks and skips any row with `is_synced = 0 OR is_deleted = 1`
(`LocalChatDao.shouldPreserveLocalRow`). Synced chat rows replaced from
remote keep their local `unread` badge count (`withPreservedUnread`;
remote rows always map with `unread = 0`). Empty remote batches return
early without touching the database.

Flush runs before refresh on every online pass, so freshly pushed rows are
already marked synced and the following refresh cannot clobber them.

## Deletion propagation

Upstream (local → remote): covered by the flush push above. Offline deletes
reach the remote on the next online pass, then disappear locally.

Downstream (remote → local): after a successful chat fetch, tombstones whose
ids are absent from the remote set are finished and pruned locally
(`hardDeleteByChat` + `hardDelete`). Tombstones still present remotely are
kept for the next upstream push. Message rows have no independent tombstone
fetch; they follow their parent chat (push deletes by chat, prune deletes
by chat).

Ghost chats (wired into `_refreshLocalCacheFromRemote` behind the
`chatsFetched` guard, after the tombstone loop): a locally-synced chat
(`is_synced = 1, is_deleted = 0`) absent from the fetched remote set was
deleted remotely without leaving a tombstone, so the tombstone loop above
never sees it. `LocalChatDao.pruneChatsGoneRemote(remoteChatIds)` covers
this case — it prunes exactly the rows where `shouldPruneLocalRow` is true
(`!existsRemotely && isSynced == 1 && isDeleted == 0`), hard-deleting each
pruned chat plus its messages, and skips any chat still holding unsynced
messages (`is_synced = 0 AND is_deleted = 0`, the `getUnsynced` filter) so
pending local work is never destroyed. Same `chatsFetched` guard applies:
only call after a successful full fetch, since `getChatsPaged` pages to a
short page and the id set is complete.

`ChatRepository.getChatsForUser` and `MessageRepository` refresh paths use
the same paginated-fetch + preserving-replace primitives, so dashboard reads
never resurrect tombstones or unsynced edits either.

## Guards

- `chatsFetched` guard: both prune steps (tombstone loop and ghost prune)
  run only when the remote chat list was actually fetched. If the fetch throws, `chatsFetched` stays false and
  pruning is skipped — an offline failure must never look like "remote
  deleted everything".
- No-uid skip: both flush and refresh read `AuthService.currentUser?.id`
  first and return immediately when it is null (offline or logged out), so
  no remote call fires without an owner id.
- M13: the worker uses only that uid snapshot and never mutates the global
  session (no login/logout/register from sync; offline-created password
  accounts stay queued for re-entry or the `sync-offline-user` edge
  function stub).
- Per-call `try/catch` around each replace/prune keeps one failing table
  from aborting the other; backoff (`_withBackoff`, 3 attempts on retryable
  errors) applies to remote calls only.

## migrateUserId schema-aware no-op

After an offline → online account claim, `migrateOfflineUserChats` re-homes
`chat_sessions` rows (`LocalChatDao.migrateUserId`: `user_id = old → new`)
and then calls `LocalMessageDao.migrateUserId`. The `messages` table has no
`user_id` column — rows are scoped by `chat_id`, so migrating the parent
chats already re-homes every message. The message migration therefore probes
`PRAGMA table_info(messages)` first and returns as a safe no-op when the
column is absent (logging in debug builds); if a future schema adds
`messages.user_id`, the same call updates it with the chat pattern. This
keeps callers crash-free (`no such column: user_id`) across schema versions.
Locked by `replaceChatsPreservingUnsynced DB integration (ffi)` and the
`no-uid skip` groups in `test/sync_service_test.dart`.
