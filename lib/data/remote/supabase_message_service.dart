import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message_model.dart';

class SupabaseMessageService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<void> saveMessage(
      String userId, String chatId, ChatMessageModel msg) async {
    await _db.from('messages').upsert({
      'id': msg.id,
      'user_id': userId,
      'chat_id': chatId,
      'text': msg.text,
      'is_user': msg.isUser,
      'timestamp': msg.timestamp.toIso8601String(),
    });
  }

  static Future<List<ChatMessageModel>> getMessages(
      String userId, String chatId) async {
    final rows = await _db
        .from('messages')
        .select()
        .eq('user_id', userId)
        .eq('chat_id', chatId)
        .order('timestamp');
    return (rows as List).map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return ChatMessageModel(
        id: data['id'] as String? ?? '',
        chatId: chatId,
        text: data['text'] as String? ?? '',
        isUser: data['is_user'] as bool? ?? false,
        timestamp:
            DateTime.tryParse(data['timestamp'] as String? ?? '') ??
                DateTime.now(),
        isSynced: true,
      );
    }).toList();
  }

  static Future<void> deleteMessages(String userId, String chatId) async {
    await _db
        .from('messages')
        .delete()
        .eq('user_id', userId)
        .eq('chat_id', chatId);
  }

  /// Paginated variant of [getMessages] for the sync path (Phase 1 primitive).
  ///
  /// Loops `.range(from, to)` — inclusive on both ends — with pages below
  /// the Supabase default 1,000-row cap until a short page signals
  /// completion. Mapping, ordering, and defaults mirror [getMessages];
  /// existing callers are untouched.
  static Future<List<ChatMessageModel>> getMessagesPaged(
    String userId,
    String chatId, {
    int pageSize = 500,
  }) async {
    final effectivePageSize = pageSize.clamp(1, 1000);
    final all = <ChatMessageModel>[];
    var page = 0;
    while (true) {
      final from = page * effectivePageSize;
      // range() is inclusive, so subtract 1 for an exact page window.
      final to = from + effectivePageSize - 1;
      final rows = await _db
          .from('messages')
          .select()
          .eq('user_id', userId)
          .eq('chat_id', chatId)
          .order('timestamp')
          .order('id')
          .range(from, to);
      final batch = (rows as List).map((row) {
        final data = Map<String, dynamic>.from(row as Map);
        return ChatMessageModel(
          id: data['id'] as String? ?? '',
          chatId: chatId,
          text: data['text'] as String? ?? '',
          isUser: data['is_user'] as bool? ?? false,
          timestamp:
              DateTime.tryParse(data['timestamp'] as String? ?? '') ??
                  DateTime.now(),
          isSynced: true,
        );
      }).toList();
      all.addAll(batch);
      if (batch.length < effectivePageSize) break;
      page++;
    }
    return all;
  }

  /// Batched whole-user fetch for the sync refresh path (Phase 2).
  ///
  /// Unlike [getMessagesPaged] (per-chat), this pages over all of a user's
  /// rows (`user_id` only) so `_refreshLocalCacheFromRemote` needs one
  /// batched call sequence per table instead of O(n+1) per-chat trips.
  /// `chat_id` is read from each row; ordering/tiebreaker mirror
  /// [getMessagesPaged]. Existing callers are untouched.
  static Future<List<ChatMessageModel>> getAllMessagesPaged(
    String userId, {
    int pageSize = 500,
  }) async {
    final effectivePageSize = pageSize.clamp(1, 1000);
    final all = <ChatMessageModel>[];
    var page = 0;
    while (true) {
      final from = page * effectivePageSize;
      // range() is inclusive, so subtract 1 for an exact page window.
      final to = from + effectivePageSize - 1;
      final rows = await _db
          .from('messages')
          .select()
          .eq('user_id', userId)
          .order('timestamp')
          .order('id')
          .range(from, to);
      final batch = (rows as List).map((row) {
        final data = Map<String, dynamic>.from(row as Map);
        return ChatMessageModel(
          id: data['id'] as String? ?? '',
          chatId: data['chat_id'] as String? ?? '',
          text: data['text'] as String? ?? '',
          isUser: data['is_user'] as bool? ?? false,
          timestamp:
              DateTime.tryParse(data['timestamp'] as String? ?? '') ??
                  DateTime.now(),
          isSynced: true,
        );
      }).toList();
      all.addAll(batch);
      if (batch.length < effectivePageSize) break;
      page++;
    }
    return all;
  }
}
