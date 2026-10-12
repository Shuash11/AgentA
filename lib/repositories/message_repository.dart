import 'package:flutter/foundation.dart';
import '../data/local/local_message_dao.dart';
import '../data/models/chat_message_model.dart';
import '../data/remote/supabase_message_service.dart';
import '../core/utils/connectivity_service.dart';

class MessageRepository {
  final LocalMessageDao _localMsgDao = LocalMessageDao.instance;
  ConnectivityService get _connectivity => ConnectivityService.instance;

  Future<String> get _userId async => _localMsgDao.getUserIdAsync();

  Future<List<ChatMessageModel>> getLocalMessages(String chatId) async {
    return await _localMsgDao.getByChat(chatId);
  }

  Future<List<ChatMessageModel>> refreshMessagesFromRemote(
    String chatId,
  ) async {
    final uid = await _userId;
    if (!await _connectivity.isOnline() || uid.isEmpty) {
      return [];
    }
    try {
      final remoteMessages = await SupabaseMessageService.getMessages(
        uid,
        chatId,
      );
      final syncedMsgs = remoteMessages
          .map((m) => m.copyWith(isSynced: true))
          .toList();
      await _localMsgDao.replaceMessagesPreservingUnsynced(syncedMsgs);
      if (kDebugMode) {
        debugPrint(
          '[MessageRepository] refresh ${remoteMessages.length} for $chatId',
        );
      }
      return remoteMessages;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '[MessageRepository] refreshMessagesFromRemote failed: $e | $stack',
        );
      }
      return [];
    }
  }

  Future<List<ChatMessageModel>> getMessages(String chatId) async {
    final isOnline = await _connectivity.isOnline();
    final uid = await _userId;

    if (isOnline && uid.isNotEmpty) {
      try {
        final remoteMessages = await SupabaseMessageService.getMessages(
          uid,
          chatId,
        );
        final syncedMsgs = remoteMessages
            .map((m) => m.copyWith(isSynced: true))
            .toList();
        await _localMsgDao.replaceMessagesPreservingUnsynced(syncedMsgs);
        return remoteMessages;
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint(
            '[MessageRepository] getMessages remote failed (keeps local): $e | $stack',
          );
        }
      }
    }

    return await _localMsgDao.getByChat(chatId);
  }

  Future<void> saveMessage(ChatMessageModel msg) async {
    await _localMsgDao.insert(msg);
    final uid = await _userId;
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseMessageService.saveMessage(uid, msg.chatId, msg);
        await _localMsgDao.update(msg.copyWith(isSynced: true));
        if (kDebugMode) {
          debugPrint('[MessageRepository] saveMessage ${msg.id} synced');
        }
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint(
            '[MessageRepository] saveMessage ${msg.id} failed keeps is_synced=0: $e | $stack',
          );
        }
        // keep is_synced=0
      }
    }
  }

  Future<void> deleteMessages(String chatId) async {
    await _localMsgDao.markDeletedByChat(chatId);
    final uid = await _userId;
    if (await _connectivity.isOnline() && uid.isNotEmpty) {
      try {
        await SupabaseMessageService.deleteMessages(uid, chatId);
        await _localMsgDao.hardDeleteByChat(chatId);
        if (kDebugMode) {
          debugPrint('[MessageRepository] deleteMessages $chatId synced');
        }
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint(
            '[MessageRepository] deleteMessages $chatId failed: $e | $stack',
          );
        }
      }
    }
  }

  Future<List<ChatMessageModel>> getUnsynced() async {
    return await _localMsgDao.getUnsynced();
  }
}
