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
}
