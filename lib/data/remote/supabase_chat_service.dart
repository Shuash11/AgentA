import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_session_model.dart';

class SupabaseChatService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<void> saveChat(String userId, ChatSessionModel chat) async {
    await _db.from('chats').upsert({
      'id': chat.id,
      'user_id': userId,
      'title': chat.title,
      'last_message': chat.lastMessage,
      'updated_at': chat.updatedAt.toIso8601String(),
    });
  }

  static Future<void> deleteChat(String userId, String chatId) async {
    await _db.from('chats').delete().eq('id', chatId).eq('user_id', userId);
  }

  /// Paginated fetch of chats for the sync path (Phase 1 primitive).
  ///
  /// Supabase applies a default 1,000-row cap per query, so a single
  /// `select()` silently drops rows for long-time users. This loops
  /// `.range(from, to)` — which is inclusive on both ends — with pages
  /// below the cap until a short page signals completion. Mapping and
  /// defaults mirror [getChatsPaged]; existing callers are untouched.
  static Future<List<ChatSessionModel>> getChatsPaged(
    String userId, {
    int pageSize = 500,
  }) async {
    final effectivePageSize = pageSize.clamp(1, 1000);
    final all = <ChatSessionModel>[];
    var page = 0;
    while (true) {
      final from = page * effectivePageSize;
      // range() is inclusive, so subtract 1 for an exact page window.
      final to = from + effectivePageSize - 1;
      final rows = await _db
          .from('chats')
          .select()
          .eq('user_id', userId)
          .order('updated_at')
          .order('id')
          .range(from, to);
      final batch = (rows as List).map((row) {
        final data = Map<String, dynamic>.from(row as Map);
        return ChatSessionModel(
          id: data['id'] as String? ?? '',
          userId: userId,
          title: data['title'] as String? ?? '',
          lastMessage: data['last_message'] as String? ?? '',
          updatedAt:
              DateTime.tryParse(data['updated_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
      all.addAll(batch);
      if (batch.length < effectivePageSize) break;
      page++;
    }
    return all;
  }
}
