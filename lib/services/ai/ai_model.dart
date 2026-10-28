// Model registry for the chat picker.
//
// cycle-36 P3: two free OpenRouter cloud models were added. The enum NAME is
// part of the contract (contracts/openrouter-ai.yaml §3): the image-model
// heuristic in chats.dart / model_picker_sheet.dart detects image models by
// the substring "pollinations" or "image", so neither new value may contain
// either substring.
enum AIModel { pollinations, groq, openrouterFlash, openrouterPro, gemma }

extension AIModelExtension on AIModel {
  String get displayName {
    switch (this) {
      case AIModel.pollinations:
        return 'AgentA Image Gen';
      case AIModel.groq:
        return 'AgentA Chatbot';
      case AIModel.openrouterFlash:
        return 'AgentA 2.1 Flash';
      case AIModel.openrouterPro:
        return 'AgentA Pro';
      case AIModel.gemma:
        return 'AgentA Offline AI';
    }
  }

  String get description {
    switch (this) {
      case AIModel.pollinations:
        return 'Generate images from text prompts';
      case AIModel.groq:
        return 'Chat with the AgentA assistant';
      case AIModel.openrouterFlash:
        return 'Fast cloud chat — free tier';
      case AIModel.openrouterPro:
        return 'Strong cloud chat — free tier';
      case AIModel.gemma:
        return 'Runs locally on your device — no internet needed';
    }
  }

  bool get isImageGeneration => this == AIModel.pollinations;
}
