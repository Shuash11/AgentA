/// Pure classifiers for chat generation errors.
///
/// Moved verbatim out of `_ChatScreenState` (`lib/presentation/chats/chats.dart`)
/// so the string→string mapping is unit-testable without widgets.
/// No behavior change: every message string here is byte-identical to the
/// pre-move text. Brand copy was normalized to "AgentA" in F23 — display-only
/// strings; if you reword them, keep the normalized brand and update the
/// `test/chat_error_classifier_test.dart` assertions.
class ChatErrorClassifier {
  const ChatErrorClassifier._();

  static const String offlineNotReadyMessage =
      'AgentA Offline AI is still getting ready. Try again in a moment.';

  /// True when the raw error text signals the offline model isn't usable yet.
  static bool isOfflineNotReady(String rawError) {
    final lower = rawError.toLowerCase();
    return lower.contains('offline model is not ready') ||
        lower.contains('offline ai model is not ready') ||
        lower.contains('offline mode is enabled') ||
        lower.contains('still getting ready') ||
        lower.contains('offline model is not installed') ||
        lower.contains('offline model failed to load');
  }

  /// Maps raw exception text to a friendly static UI string.
  ///
  /// Raw detail never reaches the UI; callers log it under `kDebugMode`.
  static String friendly(String rawError) {
    final lower = rawError.toLowerCase();

    if (isOfflineNotReady(rawError) || lower.contains('no internet')) {
      if (isOfflineNotReady(rawError)) {
        return offlineNotReadyMessage;
      }
      return 'No internet. If your offline model is installed, try again in a moment.';
    }
    if (lower.contains('groq api key not configured')) {
      return 'Chat service is not configured correctly.';
    }
    if (lower.contains('huggingface') || lower.contains('hf_token')) {
      if (lower.contains('credits exhausted') || lower.contains('rate limit')) {
        return 'HD image generation: free limit reached. Try again later or use standard image generation.';
      }
      if (lower.contains('warming up') || lower.contains('timed out')) {
        return 'HD image generation is warming up. Try again in a moment.';
      }
      if (lower.contains('not configured') || lower.contains('invalid')) {
        return 'HD image generation is not configured correctly.';
      }
      return 'HD image generation failed. Please try again.';
    }
    if (lower.contains('pollinations')) {
      return 'Image generation failed. Please try again.';
    }
    if (lower.contains('api error') || lower.contains('service error')) {
      return 'The selected AI model failed to respond. Please try again.';
    }

    return 'The selected AI model failed to respond. Please try again.';
  }
}
