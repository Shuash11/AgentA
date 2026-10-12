import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/local/local_message_dao.dart';
import '../../data/local/local_chat_dao.dart';
import '../../data/local/local_user_dao.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/chat_session_model.dart';
import '../../data/remote/supabase_message_service.dart';
import '../../data/remote/supabase_chat_service.dart';
import '../../core/utils/connectivity_service.dart';
import '../../core/utils/auth_retry.dart';
import '../auth/auth_service.dart';
import '../auth/session_manager.dart';

/// Handles offline → online sync with logging, exponential backoff,
/// and never mutates global session (M13). Keeps is_synced=0 on failure (H6).
class SyncService {
  final ConnectivityService _connectivity;
  StreamSubscription? _statusSubscription;
  bool _isSyncing = false;

  SyncService(this._connectivity);

  // Test hooks: nullable overrides for the hard-wired singletons/statics.
  // Null (the default) routes to the real `LocalChatDao.instance` /
  // `LocalMessageDao.instance` / `Supabase*Service` statics /
  // `AuthService.currentUser`, so production behavior is identical.
  // Annotated — not public API. Production logic lives in the privates.
  @visibleForTesting
  LocalChatDao? chatDaoOverrideForTest;
  @visibleForTesting
  LocalMessageDao? messageDaoOverrideForTest;
  @visibleForTesting
  String? Function()? currentUserIdOverrideForTest;
  @visibleForTesting
  Future<void> Function(String uid, ChatSessionModel chat)?
  saveChatOverrideForTest;
  @visibleForTesting
  Future<void> Function(String uid, String chatId, ChatMessageModel msg)?
  saveMessageOverrideForTest;
  @visibleForTesting
  Future<void> Function(String uid, String chatId)? deleteChatOverrideForTest;
  @visibleForTesting
  Future<List<ChatSessionModel>> Function(String uid)?
  getChatsPagedOverrideForTest;
  @visibleForTesting
  Future<List<ChatMessageModel>> Function(String uid)?
  getAllMessagesPagedOverrideForTest;

  LocalChatDao get _chatDao => chatDaoOverrideForTest ?? LocalChatDao.instance;
  LocalMessageDao get _msgDao =>
      messageDaoOverrideForTest ?? LocalMessageDao.instance;
  String? get _currentUid =>
      currentUserIdOverrideForTest?.call() ?? AuthService.currentUser?.id;

  Future<void> _saveChat(String uid, ChatSessionModel chat) =>
      saveChatOverrideForTest?.call(uid, chat) ??
      SupabaseChatService.saveChat(uid, chat);

  Future<void> _saveMessage(String uid, String chatId, ChatMessageModel msg) =>
      saveMessageOverrideForTest?.call(uid, chatId, msg) ??
      SupabaseMessageService.saveMessage(uid, chatId, msg);

  Future<void> _deleteChat(String uid, String chatId) =>
      deleteChatOverrideForTest?.call(uid, chatId) ??
      SupabaseChatService.deleteChat(uid, chatId);

  Future<List<ChatSessionModel>> _getChatsPaged(String uid) =>
      getChatsPagedOverrideForTest?.call(uid) ??
      SupabaseChatService.getChatsPaged(uid);

  Future<List<ChatMessageModel>> _getAllMessagesPaged(String uid) =>
      getAllMessagesPagedOverrideForTest?.call(uid) ??
      SupabaseMessageService.getAllMessagesPaged(uid);

  /// Test entry point for the refresh half (the flush half is covered by the
  /// public [flushPending]). Drives [_refreshLocalCacheFromRemote] with the
  /// overrides above; production has no caller.
  @visibleForTesting
  Future<void> refreshLocalCacheForTest() => _refreshLocalCacheFromRemote();

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  void init() {
    _statusSubscription?.cancel();
    _statusSubscription = _connectivity.statusStream.listen((status) async {
      if (status == InternetStatus.online && !_isSyncing) {
        _isSyncing = true;
        try {
          _log('[Sync] online detected — flushing pending');
          await _flushPending();
          await _refreshLocalCacheFromRemote();
          _log('[Sync] flush+refresh complete');
        } catch (e, st) {
          _log('[Sync] init flush failed: $e | $st');
        } finally {
          _isSyncing = false;
        }
      }
    });
  }

  void dispose() {
    _statusSubscription?.cancel();
  }

  Future<void> flushPending() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _flushPending();
    } finally {
      _isSyncing = false;
    }
  }

  /// Pending badge count API (H6) — sums unsynced chats + messages + pending users.
  /// Non-blocking, never logs PII.
  Future<int> getPendingCount() async {
    try {
      final msgCount = (await _msgDao.getUnsynced()).length;
      final chatCount = (await _chatDao.getUnsynced()).length;
      final userCount = (await LocalUserDao().getPendingSignups()).length;
      final total = msgCount + chatCount + userCount;
      _log(
        '[Sync] pendingCount msg=$msgCount chat=$chatCount user=$userCount total=$total',
      );
      return total;
    } catch (e, st) {
      _log('[Sync] getPendingCount failed: $e | $st');
      return 0;
    }
  }

  Future<Map<String, int>> getPendingBreakdown() async {
    try {
      final msgs = (await _msgDao.getUnsynced()).length;
      final chats = (await _chatDao.getUnsynced()).length;
      final users = (await LocalUserDao().getPendingSignups()).length;
      return {'messages': msgs, 'chats': chats, 'users': users};
    } catch (e) {
      _log('[Sync] getPendingBreakdown failed: $e');
      return {'messages': 0, 'chats': 0, 'users': 0};
    }
  }

  /// Exponential backoff wrapper for transient errors.
  Future<T> _withBackoff<T>(
    Future<T> Function() task,
    String label, {
    int maxAttempts = 3,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await task();
      } catch (e, st) {
        final retryable = AuthRetryPolicy.isRetryable(e);
        _log('[Sync] $label attempt $attempt failed retryable=$retryable: $e');
        if (!retryable || attempt >= maxAttempts) {
          _log('[Sync] $label giving up after $attempt | $st');
          rethrow;
        }
        final delayMs = (pow(2, attempt) * 400).toInt() + Random().nextInt(200);
        _log('[Sync] $label backing off ${delayMs}ms before retry');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  Future<void> _flushPending() async {
    await _syncPendingUsers();

    final uid = _currentUid;
    if (uid == null) {
      _log('[Sync] _flushPending skip — no uid (offline or not logged in)');
      return;
    }

    final localMsgDao = _msgDao;
    final localChatDao = _chatDao;

    final unsyncedMessages = await localMsgDao.getUnsynced();
    _log('[Sync] flushing ${unsyncedMessages.length} unsynced messages');

    for (final msg in unsyncedMessages) {
      try {
        await _withBackoff(
          () => _saveMessage(uid, msg.chatId, msg),
          'saveMessage ${msg.id}',
        );
        await localMsgDao.update(msg.copyWith(isSynced: true));
        _log('[Sync] message ${msg.id} synced');
      } catch (e, st) {
        _log('[Sync] message ${msg.id} failed (keeps is_synced=0): $e | $st');
        // keep is_synced=0 — do not mark synced on failure
      }
    }

    final unsyncedChats = await localChatDao.getUnsynced();
    _log('[Sync] flushing ${unsyncedChats.length} unsynced chats');
    for (final chat in unsyncedChats) {
      try {
        await _withBackoff(() => _saveChat(uid, chat), 'saveChat ${chat.id}');
        await localChatDao.update(chat.copyWith(isSynced: true));
        _log('[Sync] chat ${chat.id} synced');
      } catch (e, st) {
        _log('[Sync] chat ${chat.id} failed (keeps is_synced=0): $e | $st');
      }
    }

    // Upstream deletion propagation (Phase 2): push offline tombstones
    // (is_deleted=1, is_synced=0) to remote, then hard-delete locally.
    // H6: failure keeps the tombstone pending for the next pass.
    // M13: uses only the local uid snapshot above — never mutates session.
    final tombstonedChats = await localChatDao.getTombstonedChats();
    final pendingDeletes = tombstonedChats
        .where((chat) => !chat.isSynced)
        .toList();
    _log('[Sync] flushing ${pendingDeletes.length} tombstoned chats');
    for (final chat in pendingDeletes) {
      try {
        await _withBackoff(
          () => _deleteChat(uid, chat.id),
          'deleteChat ${chat.id}',
        );
        await localMsgDao.hardDeleteByChat(chat.id);
        await localChatDao.hardDelete(chat.id);
        _log('[Sync] chat ${chat.id} delete synced (hard-deleted locally)');
      } catch (e, st) {
        _log('[Sync] chat ${chat.id} delete failed (tombstone kept): $e | $st');
      }
    }
  }

  Future<void> _syncPendingUsers() async {
    final localUserDao = LocalUserDao();
    List<Map<String, dynamic>> pendingSignups;
    try {
      pendingSignups = await localUserDao.getPendingSignups();
    } catch (e, st) {
      _log('[Sync] getPendingSignups failed: $e | $st');
      return;
    }
    _log('[Sync] pendingSignups count=${pendingSignups.length}');
    final session = await SessionManager.currentSession();

    for (final signup in pendingSignups) {
      try {
        final localId = signup['local_id'] as String;
        final email = signup['email'] as String;
        final provider = (signup['provider'] as String?) ?? 'password';

        if (provider == 'google') {
          try {
            await localUserDao.markAsSynced(localId, localId);
            _log('[Sync] google pending $localId marked synced');
          } catch (e, st) {
            _log('[Sync] google markAsSynced failed $localId: $e | $st');
          }
          continue;
        }

        if (session == null ||
            session.email.trim().toLowerCase() != email.trim().toLowerCase()) {
          _log(
            '[Sync] skip pending $localId — session mismatch (needs re-login)',
          );
          continue;
        }

        // M13: never mutate global session, never call login/logout in worker.
        // Offline-created password accounts are queued for user re-entry or
        // Edge Function stub below. Clean legacy stashed key best-effort.
        await SessionManager.dropStashedPassword(localId);
        _log(
          '[Sync] pending $localId queued (needs password re-entry / Edge Function)',
        );
        // Edge Function stub: when deployed, call Supabase Edge Function
        // `sync-offline-user` with {local_id, email} using service role,
        // instead of client-side register/login.
        await _queueForEdgeFunction(localId, email);
      } catch (e, st) {
        _log('[Sync] _syncPendingUsers item failed: $e | $st');
      }
    }
  }

  /// Stub for Edge Function path — logs and keeps is_synced=0.
  ///
  /// TODO: a `sync-offline-user` Supabase Edge Function is REQUIRED for
  /// offline-created accounts to ever sync — it cannot be implemented
  /// client-side (register/login from the sync worker is forbidden, see M13).
  /// When deployed, replace this stub with:
  ///   Supabase.instance.client.functions.invoke('sync-offline-user',
  ///       body: {'local_id': localId, 'email': email})
  /// Until then, [getPendingCount] keeps reporting these rows and they stay
  /// queued (is_synced=0) for the next sync pass.
  Future<void> _queueForEdgeFunction(String localId, String email) async {
    _log(
      '[Sync] EdgeFunction queue stub localId=${localId.substring(0, localId.length > 6 ? 6 : localId.length)}*** emailLen=${email.length}',
    );
    // No-op until Edge Function deployed — pending row stays unsynced.
  }

  /// Batched refresh (Phase 2): one paginated fetch per table, one batch
  /// replace per table. Never resurrects tombstones/unsynced rows
  /// (`replace*PreservingUnsynced` skips `is_synced=0 OR is_deleted=1`).
  Future<void> _refreshLocalCacheFromRemote() async {
    final uid = _currentUid;
    if (uid == null) {
      _log('[Sync] _refreshLocalCacheFromRemote skip — no uid');
      return;
    }

    final localChatDao = _chatDao;
    final localMsgDao = _msgDao;

    // Only prune tombstones when the remote chat list was actually fetched;
    // otherwise an offline failure would look like "remote deleted all".
    var chatsFetched = false;
    var remoteChatIds = <String>{};

    try {
      final remoteChats = await _withBackoff(
        () => _getChatsPaged(uid),
        'getChatsPaged',
      );
      final syncedChats = remoteChats
          .map((chat) => chat.copyWith(isSynced: true))
          .toList();
      try {
        await localChatDao.replaceChatsPreservingUnsynced(syncedChats);
      } catch (e, st) {
        _log('[Sync] replaceChatsPreservingUnsynced failed: $e | $st');
      }
      remoteChatIds = syncedChats.map((chat) => chat.id).toSet();
      chatsFetched = true;
      _log(
        '[Sync] refreshed ${syncedChats.length} chats from remote (paged, batched)',
      );
    } catch (e, st) {
      _log('[Sync] getChatsPaged failed: $e | $st');
    }

    try {
      final remoteMessages = await _withBackoff(
        () => _getAllMessagesPaged(uid),
        'getAllMessagesPaged',
      );
      final syncedMessages = remoteMessages
          .map((msg) => msg.copyWith(isSynced: true))
          .toList();
      try {
        await localMsgDao.replaceMessagesPreservingUnsynced(syncedMessages);
      } catch (e, st) {
        _log('[Sync] replaceMessagesPreservingUnsynced failed: $e | $st');
      }
      _log(
        '[Sync] refreshed ${syncedMessages.length} messages from remote (paged, batched)',
      );
    } catch (e, st) {
      _log('[Sync] getAllMessagesPaged failed: $e | $st');
    }

    // Downstream deletion propagation: tombstones whose rows are gone
    // remotely are finished — hard-delete the chat + its messages locally.
    // Tombstones still present remotely are kept for the next upstream push.
    // Invariant: `getChatsPaged` loops until a short page, so a completed
    // fetch means `remoteChatIds` is complete; any page failure throws and
    // leaves `chatsFetched=false`, so an offline failure never looks like
    // "remote deleted everything".
    if (!chatsFetched) {
      _log('[Sync] downstream prune skipped — remote chat list unavailable');
      return;
    }
    try {
      final tombstones = await localChatDao.getTombstonedChats();
      var pruned = 0;
      for (final tombstone in tombstones) {
        if (remoteChatIds.contains(tombstone.id)) continue;
        try {
          await localMsgDao.hardDeleteByChat(tombstone.id);
          await localChatDao.hardDelete(tombstone.id);
          pruned++;
        } catch (e, st) {
          _log('[Sync] prune tombstone ${tombstone.id} failed: $e | $st');
        }
      }
      _log('[Sync] pruned $pruned tombstoned chats (remote gone)');
    } catch (e, st) {
      _log('[Sync] downstream prune failed: $e | $st');
    }
    // Ghost-chat prune: synced-but-alive rows absent remotely were deleted
    // remotely without leaving a tombstone, so the loop above never sees
    // them. Filters are disjoint (`shouldPruneLocalRow` is true only for
    // is_synced=1, is_deleted=0 rows), so running after the tombstone loop
    // is safe. Same `chatsFetched` guard applies — never runs after a
    // fetch failure. Skips chats holding unsynced messages, so pending
    // local work is never destroyed.
    try {
      final ghostsPruned = await localChatDao.pruneChatsGoneRemote(
        remoteChatIds,
      );
      _log('[Sync] pruned $ghostsPruned ghost chats (remote gone)');
    } catch (e, st) {
      _log('[Sync] ghost prune failed: $e | $st');
    }
  }

  Future<void> migrateOfflineUserChats(
    String oldOfflineId,
    String newSupabaseId,
  ) async {
    final localChatDao = _chatDao;
    final localMsgDao = _msgDao;
    try {
      await localChatDao.migrateUserId(oldOfflineId, newSupabaseId);
      await localMsgDao.migrateUserId(oldOfflineId, newSupabaseId);
      _log('[Sync] migrate $oldOfflineId -> $newSupabaseId done');
    } catch (e, st) {
      _log('[Sync] migrate failed: $e | $st');
    }
  }
}
