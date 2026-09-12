// ignore_for_file: empty_catches
import 'dart:async';
import '../../data/local/local_message_dao.dart';
import '../../data/local/local_chat_dao.dart';
import '../../data/local/local_user_dao.dart';
import '../../data/remote/supabase_message_service.dart';
import '../../data/remote/supabase_chat_service.dart';
import '../../core/utils/connectivity_service.dart';
import '../auth/auth_service.dart';
import '../../repositories/user_repository.dart';
import '../auth/session_manager.dart';

class SyncService {
  final ConnectivityService _connectivity;
  StreamSubscription? _statusSubscription;
  bool _isSyncing = false;

  SyncService(this._connectivity);

  void init() {
    _statusSubscription?.cancel();
    _statusSubscription = _connectivity.statusStream.listen((status) async {
      if (status == InternetStatus.online && !_isSyncing) {
        
        _isSyncing = true;
        try {
          await _flushPending();
          await _refreshLocalCacheFromRemote();
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

  Future<void> _flushPending() async {
    await _syncPendingUsers();

    final uid = AuthService.currentUser?.id;
    if (uid == null) return;

    final localMsgDao = LocalMessageDao.instance;
    final localChatDao = LocalChatDao.instance;

    final unsyncedMessages = await localMsgDao.getUnsynced();

    for (final msg in unsyncedMessages) {
      try {
        await SupabaseMessageService.saveMessage(uid, msg.chatId, msg);
        await localMsgDao.update(msg.copyWith(isSynced: true));
      } catch (e) {
        
      }
    }

    final unsyncedChats = await localChatDao.getUnsynced();
    for (final chat in unsyncedChats) {
      try {
        await SupabaseChatService.saveChat(uid, chat);
        await localChatDao.update(chat.copyWith(isSynced: true));
      } catch (e) {
        
      }
    }
  }

  Future<void> _syncPendingUsers() async {
    final localUserDao = LocalUserDao();
    final pendingSignups = await localUserDao.getPendingSignups();
    final session = await SessionManager.currentSession();

    for (final signup in pendingSignups) {
      try {
        final localId = signup['local_id'] as String;
        final email = signup['email'] as String;
        final provider = (signup['provider'] as String?) ?? 'password';
        final displayName = signup['display_name'] as String;
        final recoveryCode = signup['recovery_code'] as String;

        if (provider == 'google') {
          await localUserDao.markAsSynced(localId, localId);
          continue;
        }

        if (session == null ||
            session.email.trim().toLowerCase() !=
                email.trim().toLowerCase()) {
          continue;
        }

        final password =
            await SessionManager.takeStashedPassword(localId) ?? '';
        if (password.isEmpty) {
          continue;
        }

        String supabaseUid;
        try {
          final cred =
              await AuthService.register(email, password, displayName);
          supabaseUid = cred.uid;
          await UserRepository.createUserProfile(
              supabaseUid, email, displayName, recoveryCode);
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (!(msg.contains('already registered') ||
              msg.contains('already exists') ||
              msg.contains('user already'))) {
            rethrow;
          }
          final cred = await AuthService.login(email, password);
          supabaseUid = cred.uid;
          await AuthService.signOutOnly();
        }

        await localUserDao.markAsSynced(localId, supabaseUid);
        await SessionManager.dropStashedPassword(localId);
        if (localId != supabaseUid) {
          await migrateOfflineUserChats(localId, supabaseUid);
        }
        await SessionManager.saveSession(
          uid: supabaseUid,
          email: email,
          provider: 'password',
        );
      } catch (_) {}
    }
  }

  Future<void> _refreshLocalCacheFromRemote() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) return;

    final localChatDao = LocalChatDao.instance;
    final localMsgDao = LocalMessageDao.instance;

    try {
      final remoteChats = await SupabaseChatService.getChats(uid);
      for (final chat in remoteChats) {
        final syncedChat = chat.copyWith(isSynced: true);
        await localChatDao.replaceChat(chat.id, syncedChat);
      }
    } catch (e) {
      
    }

    try {
      final chats = await localChatDao.getByUserId(uid);
      for (final chat in chats) {
        try {
          final remoteMessages = await SupabaseMessageService.getMessages(uid, chat.id);
          for (final msg in remoteMessages) {
            await localMsgDao.replaceMessage(msg.id, msg.copyWith(isSynced: true));
          }
        } catch (e) {
          
        }
      }
    } catch (e) {
      
    }
  }

  Future<void> migrateOfflineUserChats(String oldOfflineId, String newSupabaseId) async {
    final localChatDao = LocalChatDao.instance;
    final localMsgDao = LocalMessageDao.instance;

    await localChatDao.migrateUserId(oldOfflineId, newSupabaseId);
    await localMsgDao.migrateUserId(oldOfflineId, newSupabaseId);
  }
}