// ignore_for_file: empty_catches
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
    final isOnline = await _connectivity.isOnline();

    if (isOnline && userId.isNotEmpty && !userId.startsWith('offline_')) {
      try {
        final remoteChats = await SupabaseChatService.getChats(userId);
        for (final chat in remoteChats) {
          final syncedChat = chat.copyWith(isSynced: true);
          await _localChatDao.replaceChat(chat.id, syncedChat);
        }
        return remoteChats;
      } catch (e) {}
    }

    if (userId.isEmpty) {
      return await _localChatDao.getAllChats();
    }
    return await _localChatDao.getByUserId(userId);
  }

  Future<ChatSessionModel?> getChat(String chatId) async {
    return await _localChatDao.getById(chatId);
  }

  Future<void> createChat(ChatSessionModel chat) async {
    await _localChatDao.insert(chat);
    final uid = await _userId;
    if (uid.isNotEmpty && uid.startsWith('offline_')) {
      return;
    }
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseChatService.saveChat(uid, chat);
        await _localChatDao.update(chat.copyWith(isSynced: true));
      } catch (e) {}
    }
  }

  Future<void> updateChat(ChatSessionModel chat) async {
    await _localChatDao.update(chat);
    final uid = await _userId;
    if (uid.isNotEmpty && uid.startsWith('offline_')) {
      return;
    }
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseChatService.saveChat(uid, chat);
        await _localChatDao.update(chat.copyWith(isSynced: true));
      } catch (e) {}
    }
  }

  Future<void> deleteChat(String userId, String chatId) async {
    await _localChatDao.markDeleted(chatId);
    final uid = await _userId;
    if (uid.isNotEmpty && uid.startsWith('offline_')) {
      return;
    }
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseChatService.deleteChat(uid, chatId);
        await _localChatDao.hardDelete(chatId);
      } catch (e) {}
    }
  }

  Future<List<ChatSessionModel>> getUnsynced() async {
    return await _localChatDao.getUnsynced();
  }
}