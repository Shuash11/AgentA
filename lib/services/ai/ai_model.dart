enum AIModel { pollinations, groq, minimax, gemma }

extension AIModelExtension on AIModel {
  String get displayName {
    switch (this) {
      case AIModel.pollinations:
        return 'Image Gen';
      case AIModel.groq:
        return 'Groq';
      case AIModel.minimax:
        return 'MiniMax';
      case AIModel.gemma:
        return 'Gemma';
    }
  }

  String get description {
    switch (this) {
      case AIModel.pollinations:
        return 'Pollinations AI - Generate images';
      case AIModel.groq:
        return 'Groq - Llama 3.3 70B';
      case AIModel.minimax:
        return 'MiniMax - abab6.5s';
      case AIModel.gemma:
        return 'Gemma - Local Offline AI';
    }
  }

  bool get isImageGeneration => this == AIModel.pollinations;
}
