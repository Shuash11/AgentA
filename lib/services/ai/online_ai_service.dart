import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../data/models/chat_message_model.dart';
import 'ai_model.dart';
import 'groq_service.dart';
import 'huggingface_image_service.dart';
import 'openrouter_service.dart';
import 'pollinations_service.dart';

class OnlineAIService extends ChangeNotifier {
  final GroqService _groq;
  final OpenRouterService _openRouter;
  final PollinationsService _pollinations;
  final HuggingFaceImageService _huggingFace;

  AIModel _preferredModel = AIModel.groq;

  OnlineAIService(
    this._groq,
    this._openRouter,
    this._pollinations,
    this._huggingFace,
  );

  AIModel get preferredModel => _preferredModel;

  void setPreferredModel(AIModel model) {
    if (_preferredModel == model) return;
    _preferredModel = model;

    notifyListeners();
  }

  void clearPreferredModel() {
    if (_preferredModel == AIModel.groq) return;
    _preferredModel = AIModel.groq;

    notifyListeners();
  }

  Future<String> sendMessage({
    required List<ChatMessageModel> history,
    required String newMessage,
    AIModel? model,
  }) async {
    final selectedModel = model ?? _preferredModel;

    switch (selectedModel) {
      case AIModel.pollinations:
        return _pollinations.generateImage(prompt: newMessage);
      case AIModel.groq:
        return _groq.sendMessage(history: history, newMessage: newMessage);
      case AIModel.openrouterFlash:
        return _openRouter.sendMessage(
          history: history,
          newMessage: newMessage,
          model: AppConfig.openRouterFlashModel,
        );
      case AIModel.openrouterPro:
        return _openRouter.sendMessage(
          history: history,
          newMessage: newMessage,
          model: AppConfig.openRouterProModel,
        );
      case AIModel.gemma:
        throw Exception(
          'AgentA Offline AI is an offline model and cannot be used while online.',
        );
    }
  }

  Stream<String> sendMessageStream({
    required List<ChatMessageModel> history,
    required String newMessage,
    AIModel? model,
  }) async* {
    final selectedModel = model ?? _preferredModel;

    switch (selectedModel) {
      case AIModel.pollinations:
        yield await _pollinations.generateImage(prompt: newMessage);
        return;
      case AIModel.groq:
        yield* _groq.sendMessageStream(
          history: history,
          newMessage: newMessage,
        );
        return;
      case AIModel.openrouterFlash:
        yield* _openRouter.sendMessageStream(
          history: history,
          newMessage: newMessage,
          model: AppConfig.openRouterFlashModel,
        );
        return;
      case AIModel.openrouterPro:
        yield* _openRouter.sendMessageStream(
          history: history,
          newMessage: newMessage,
          model: AppConfig.openRouterProModel,
        );
        return;
      case AIModel.gemma:
        throw Exception(
          'AgentA Offline AI is an offline model and cannot be used while online.',
        );
    }
  }

  String buildImageUrl(String prompt) {
    return _pollinations.buildImageUrl(prompt: prompt);
  }

  bool get isHuggingFaceAvailable => _huggingFace.isConfigured;

  Future<String> generateImageFallback(String prompt) {
    return _huggingFace.generateImageFile(prompt: prompt);
  }

  void cancelActiveGeneration() {
    _groq.cancelGeneration();
    _openRouter.cancelGeneration();
    _huggingFace.cancelGeneration();
  }
}
