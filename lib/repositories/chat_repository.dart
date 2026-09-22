import 'package:flutter/foundation.dart';
import '../data/local/local_chat_dao.dart';
import '../data/models/chat_session_model.dart';
import '../data/remote/supabase_chat_service.dart';
import '../core/utils/connectivity_service.dart';

class ChatRepository {
  final LocalChatDao _localChatDao = LocalChatDao.instance;
  ConnectivityService get _connectivity => ConnectivityService.instance;

  Future<String> get _userId async {
    final uid = await _localChatDao.getUserId();
    return uid;
  }

  Future<List<ChatSessionModel>> getChatsForUser(String userId) async {
    if (userId.isEmpty) {
      return [];
    }
    final local = await _localChatDao.getByUserId(userId);
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) {
      return local;
    }

    // Dashboard path uses the same Phase 2 primitives as the sync worker:
    // paginated fetch + preserving batch replace, so offline deletes and
    // unsynced edits are never resurrected here either.
    try {
      final remoteChats = await SupabaseChatService.getChatsPaged(userId);
      final syncedChats =
          remoteChats.map((chat) => chat.copyWith(isSynced: true)).toList();
      await _localChatDao.replaceChatsPreservingUnsynced(syncedChats);
      // Re-read: synced rows are now present, tombstones/unsynced locals
      // untouched (replace skips them, query filters tombstones out).
      final fresh = await _localChatDao.getByUserId(userId);
      if (kDebugMode) {
        debugPrint('[ChatRepository] getChatsForUser merged ${fresh.length}');
      }
      return fresh;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[ChatRepository] getChatsForUser remote failed: $e | $stack');
    }
    return local;
  }

  Future<ChatSessionModel?> getChat(String chatId) async {
    return await _localChatDao.getById(chatId);
  }

  Future<void> createChat(ChatSessionModel chat) async {
    await _localChatDao.insert(chat);
    final uid = await _userId;
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseChatService.saveChat(uid, chat);
        await _localChatDao.update(chat.copyWith(isSynced: true));
        if (kDebugMode) debugPrint('[ChatRepository] createChat ${chat.id} synced');
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[ChatRepository] createChat ${chat.id} failed keeps is_synced=0: $e | $stack');
      }
    }
  }

  Future<void> updateChat(ChatSessionModel chat) async {
    await _localChatDao.update(chat);
    final uid = await _userId;
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseChatService.saveChat(uid, chat);
        await _localChatDao.update(chat.copyWith(isSynced: true));
        if (kDebugMode) debugPrint('[ChatRepository] updateChat ${chat.id} synced');
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[ChatRepository] updateChat ${chat.id} failed: $e | $stack');
      }
    }
  }

  Future<void> deleteChat(String userId, String chatId) async {
    await _localChatDao.markDeleted(chatId);
    final uid = await _userId;
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseChatService.deleteChat(uid, chatId);
        await _localChatDao.hardDelete(chatId);
        if (kDebugMode) debugPrint('[ChatRepository] deleteChat $chatId synced');
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[ChatRepository] deleteChat $chatId failed: $e | $stack');
      }
    }
  }

  Future<List<ChatSessionModel>> getUnsynced() async {
    return await _localChatDao.getUnsynced();
  }
}
