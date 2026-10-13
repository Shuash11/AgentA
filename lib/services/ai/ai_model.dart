enum AIModel { pollinations, groq, gemma }

extension AIModelExtension on AIModel {
  String get displayName {
    switch (this) {
      case AIModel.pollinations:
        return 'AgentA Image Gen';
      case AIModel.groq:
        return 'AgentA Chatbot';
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
      case AIModel.gemma:
        return 'Runs locally on your device — no internet needed';
    }
  }

  bool get isImageGeneration => this == AIModel.pollinations;
}
