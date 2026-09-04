import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message_model.dart';

class FirestoreMessageService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> saveMessage(String userId, String chatId, ChatMessageModel msg) async {
    await _db.collection('users').doc(userId).collection('chats').doc(chatId).collection('messages').doc(msg.id).set(msg.toFirestore(userId));
  }

  static Future<List<ChatMessageModel>> getMessages(String userId, String chatId) async {
    final snapshot = await _db.collection('users').doc(userId).collection('chats').doc(chatId).collection('messages').orderBy('timestamp').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ChatMessageModel(
        id: doc.id,
        chatId: chatId,
        text: data['text'] ?? '',
        isUser: data['is_user'] ?? false,
        timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isSynced: true,
      );
    }).toList();
  }

  static Future<void> deleteMessages(String userId, String chatId) async {
    final batch = _db.batch();
    final snapshot = await _db.collection('users').doc(userId).collection('chats').doc(chatId).collection('messages').get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}