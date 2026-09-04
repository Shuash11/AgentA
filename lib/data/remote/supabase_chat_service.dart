// ignore_for_file: empty_catches
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

  static Future<List<ChatSessionModel>> getChats(String userId) async {
    final rows = await _db.from('chats').select().eq('user_id', userId);
    return (rows as List).map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      return ChatSessionModel(
        id: data['id'] as String? ?? '',
        userId: userId,
        title: data['title'] as String? ?? '',
        lastMessage: data['last_message'] as String? ?? '',
        updatedAt: DateTime.tryParse(data['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }

  static Future<void> deleteChat(String userId, String chatId) async {
    await _db.from('chats').delete().eq('id', chatId).eq('user_id', userId);
  }
}
