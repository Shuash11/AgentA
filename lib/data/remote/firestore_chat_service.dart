import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_session_model.dart';

class FirestoreChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> saveChat(String userId, ChatSessionModel chat) async {
    await _db.collection('users').doc(userId).collection('chats').doc(chat.id).set(chat.toFirestore());
  }

  static Future<List<ChatSessionModel>> getChats(String userId) async {
    final snapshot = await _db.collection('users').doc(userId).collection('chats').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ChatSessionModel(
        id: doc.id,
        userId: userId,
        title: data['title'] ?? '',
        lastMessage: data['last_message'] ?? '',
        updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  static Future<void> deleteChat(String userId, String chatId) async {
    await _db.collection('users').doc(userId).collection('chats').doc(chatId).delete();
  }
}