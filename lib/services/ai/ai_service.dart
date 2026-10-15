import 'dart:async';
import '../../core/utils/ai_output_guard.dart';
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

  String? get offlineModelProblem => _offlineAI.offlineModelProblem;

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
    if (!isOfflineModelReady) return 'AgentA Offline AI not ready';
    return 'AgentA Offline AI';
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
    final String response;
    if (isOnline) {
      response = await _onlineAI.sendMessage(
        history: history,
        newMessage: newMessage,
        model: model,
      );
    } else {
      final offlineReady = await _offlineAI.ensureReady();
      if (!offlineReady) {
        throw Exception(
          'No internet and offline model not ready. ${offlineModelProblem ?? 'Please download the offline model first.'}',
        );
      }

      response = await _offlineAI.sendMessage(
        history: history,
        newMessage: newMessage,
      );
    }

    // F29: strip trailing prompt-meta artifacts before the response can be
    // displayed or persisted.
    return AiOutputGuard.stripPromptArtifacts(response);
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
    AIModel? model,
  }) async* {
    // F29: the guard withholds a potential trailing artifact until the
    // stream completes, so the artifact is never emitted to the UI.
    if (isOnline) {
      yield* AiOutputGuard.guardStream(
        _onlineAI.sendMessageStream(
          history: history,
          newMessage: newMessage,
          model: model,
        ),
      );
    } else {
      final offlineReady = await _offlineAI.ensureReady();
      if (!offlineReady) {
        throw Exception(
          'No internet and offline model not ready. ${offlineModelProblem ?? 'Please download the offline model first.'}',
        );
      }

      yield* AiOutputGuard.guardStream(
        _offlineAI.sendMessageStream(history: history, newMessage: newMessage),
      );
    }
  }

  String buildImageUrl(String prompt) {
    return _onlineAI.buildImageUrl(prompt);
  }

  bool get isHuggingFaceAvailable => _onlineAI.isHuggingFaceAvailable;

  Future<String> generateImageFallback(String prompt) {
    return _onlineAI.generateImageFallback(prompt);
  }

  Future<void> resetOfflineSession() => _offlineAI.resetSession();

  void cancelActiveGeneration() {
    _offlineAI.cancelActiveGeneration();
    _onlineAI.cancelActiveGeneration();
  }
}
