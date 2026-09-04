import 'dart:async';
import '../../core/utils/connectivity_service.dart';
import '../../data/models/chat_message_model.dart';
import 'ai_model.dart';
import 'offline_ai_service.dart';
import 'online_ai_service.dart';

class AIService {
  final OfflineAIService _offlineAI;
  final OnlineAIService _onlineAI;
  final ConnectivityService _connectivity;

  AIService(this._offlineAI, this._onlineAI, this._connectivity);

  bool get isOnline => _connectivity.lastStatus == InternetStatus.online;

  bool get isOfflineModelReady => _offlineAI.isReady;

  AIModel get activeModel {
    if (isOnline) {
      return _onlineAI.preferredModel;
    }
    return AIModel.gemma;
  }

  AIModel get preferredModel => _onlineAI.preferredModel;

  String get currentModelName {
    if (isOnline) {
      return _onlineAI.preferredModel.displayName;
    }
    if (!isOfflineModelReady) return 'Offline - model not ready';
    return 'Gemma (Offline)';
  }

  void setPreferredModel(AIModel model) {
    _onlineAI.setPreferredModel(model);
  }

  void clearPreferredModel() {
    _onlineAI.clearPreferredModel();
  }

  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
    AIModel? model,
  }) async {
    if (isOnline) {
      
      return _onlineAI.sendMessage(
        history: history,
        newMessage: newMessage,
        model: model,
      );
    } else {
      final offlineReady = await _offlineAI.ensureReady();
      if (!offlineReady) {
        throw Exception('No internet and offline model not ready. Please download the Gemma model first.');
      }
      
      return _offlineAI.sendMessage(history: history, newMessage: newMessage);
    }
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
    AIModel? model,
  }) async* {
    if (isOnline) {
      
      yield* _onlineAI.sendMessageStream(
        history: history,
        newMessage: newMessage,
        model: model,
      );
    } else {
      final offlineReady = await _offlineAI.ensureReady();
      if (!offlineReady) {
        throw Exception('No internet and offline model not ready. Please download the Gemma model first.');
      }
      
      yield* _offlineAI.sendMessageStream(history: history, newMessage: newMessage);
    }
  }

  String buildImageUrl(String prompt) {
    return _onlineAI.buildImageUrl(prompt);
  }

  Future<void> resetOfflineSession() => _offlineAI.resetSession();

  void cancelActiveGeneration() {
    _offlineAI.cancelActiveGeneration();
    _onlineAI.cancelActiveGeneration();
  }
}