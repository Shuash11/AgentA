enum AIModel { pollinations, groq, gemma }

extension AIModelExtension on AIModel {
  String get displayName {
    switch (this) {
      case AIModel.pollinations:
        return 'Agenta Image Gen';
      case AIModel.groq:
        return 'Agenta Chatbot';
      case AIModel.gemma:
        return 'Agenta Offline AI';
    }
  }

  String get description {
    switch (this) {
      case AIModel.pollinations:
        return 'Generate images from text prompts';
      case AIModel.groq:
        return 'Chat with the Agenta assistant';
      case AIModel.gemma:
        return 'Runs locally on your device — no internet needed';
    }
  }

  bool get isImageGeneration => this == AIModel.pollinations;
}
