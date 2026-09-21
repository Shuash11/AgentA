import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/local/local_message_dao.dart';
import '../../data/local/local_chat_dao.dart';
import '../../data/local/local_user_dao.dart';
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
      final msgCount = (await LocalMessageDao.instance.getUnsynced()).length;
      final chatCount = (await LocalChatDao.instance.getUnsynced()).length;
      final userCount = (await LocalUserDao().getPendingSignups()).length;
      final total = msgCount + chatCount + userCount;
      _log('[Sync] pendingCount msg=$msgCount chat=$chatCount user=$userCount total=$total');
      return total;
    } catch (e, st) {
      _log('[Sync] getPendingCount failed: $e | $st');
      return 0;
    }
  }

  Future<Map<String, int>> getPendingBreakdown() async {
    try {
      final msgs = (await LocalMessageDao.instance.getUnsynced()).length;
      final chats = (await LocalChatDao.instance.getUnsynced()).length;
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

    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      _log('[Sync] _flushPending skip — no uid (offline or not logged in)');
      return;
    }

    final localMsgDao = LocalMessageDao.instance;
    final localChatDao = LocalChatDao.instance;

    final unsyncedMessages = await localMsgDao.getUnsynced();
    _log('[Sync] flushing ${unsyncedMessages.length} unsynced messages');

    for (final msg in unsyncedMessages) {
      try {
        await _withBackoff(
          () => SupabaseMessageService.saveMessage(uid, msg.chatId, msg),
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
        await _withBackoff(
          () => SupabaseChatService.saveChat(uid, chat),
          'saveChat ${chat.id}',
        );
        await localChatDao.update(chat.copyWith(isSynced: true));
        _log('[Sync] chat ${chat.id} synced');
      } catch (e, st) {
        _log('[Sync] chat ${chat.id} failed (keeps is_synced=0): $e | $st');
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
          _log('[Sync] skip pending $localId — session mismatch (needs re-login)');
          continue;
        }

        // M13: never mutate global session, never call login/logout in worker.
        // Offline-created password accounts are queued for user re-entry or
        // Edge Function stub below. Clean legacy stashed key best-effort.
        await SessionManager.dropStashedPassword(localId);
        _log('[Sync] pending $localId queued (needs password re-entry / Edge Function)');
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
    _log('[Sync] EdgeFunction queue stub localId=${localId.substring(0, localId.length > 6 ? 6 : localId.length)}*** emailLen=${email.length}');
    // No-op until Edge Function deployed — pending row stays unsynced.
  }

  Future<void> _refreshLocalCacheFromRemote() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      _log('[Sync] _refreshLocalCacheFromRemote skip — no uid');
      return;
    }

    final localChatDao = LocalChatDao.instance;
    final localMsgDao = LocalMessageDao.instance;

    try {
      final remoteChats = await _withBackoff(
        () => SupabaseChatService.getChats(uid),
        'getChats',
      );
      for (final chat in remoteChats) {
        final syncedChat = chat.copyWith(isSynced: true);
        try {
          await localChatDao.replaceChat(chat.id, syncedChat);
        } catch (e, st) {
          _log('[Sync] replaceChat ${chat.id} failed: $e | $st');
        }
      }
      _log('[Sync] refreshed ${remoteChats.length} chats from remote');
    } catch (e, st) {
      _log('[Sync] getChats failed: $e | $st');
    }

    try {
      final chats = await localChatDao.getByUserId(uid);
      for (final chat in chats) {
        try {
          final remoteMessages = await _withBackoff(
            () => SupabaseMessageService.getMessages(uid, chat.id),
            'getMessages ${chat.id}',
          );
          for (final msg in remoteMessages) {
            try {
              await localMsgDao.replaceMessage(msg.id, msg.copyWith(isSynced: true));
            } catch (e, st) {
              _log('[Sync] replaceMessage ${msg.id} failed: $e | $st');
            }
          }
        } catch (e, st) {
          _log('[Sync] getMessages for chat ${chat.id} failed: $e | $st');
        }
      }
    } catch (e, st) {
      _log('[Sync] _refreshLocalCache outer failed: $e | $st');
    }
  }

  Future<void> migrateOfflineUserChats(String oldOfflineId, String newSupabaseId) async {
    final localChatDao = LocalChatDao.instance;
    final localMsgDao = LocalMessageDao.instance;
    try {
      await localChatDao.migrateUserId(oldOfflineId, newSupabaseId);
      await localMsgDao.migrateUserId(oldOfflineId, newSupabaseId);
      _log('[Sync] migrate $oldOfflineId -> $newSupabaseId done');
    } catch (e, st) {
      _log('[Sync] migrate failed: $e | $st');
    }
  }
}
