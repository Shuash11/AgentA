enum AIModel { pollinations, groq, gemma }

extension AIModelExtension on AIModel {
  String get displayName {
    switch (this) {
      case AIModel.pollinations:
        return 'Image Gen';
      case AIModel.groq:
        return 'Groq';
      case AIModel.gemma:
        return 'Gemma';
    }
  }

  String get description {
    switch (this) {
      case AIModel.pollinations:
        return 'Pollinations AI - Generate images';
      case AIModel.groq:
        return 'Groq - ALLaM 2 7B';
      case AIModel.gemma:
        return 'Gemma - Local Offline AI';
    }
  }

  bool get isImageGeneration => this == AIModel.pollinations;
}
