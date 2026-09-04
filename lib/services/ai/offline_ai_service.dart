import '../../data/models/chat_message_model.dart';
import 'gemma_service.dart';

class OfflineAIService {
  final GemmaService _gemma;

  OfflineAIService(this._gemma);

  bool get isReady => _gemma.isReady;

  Future<bool> ensureReady() => _gemma.ensureReady();

  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) {
    return _gemma.sendMessage(history: history, newMessage: newMessage);
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
  }) {
    return _gemma.sendMessageStream(history: history, newMessage: newMessage);
  }

  Future<void> loadInstalled() => _gemma.loadInstalled();

  Future<void> resetSession() => _gemma.resetSession();

  void cancelActiveGeneration() {
    _gemma.cancelGeneration();
  }
}
