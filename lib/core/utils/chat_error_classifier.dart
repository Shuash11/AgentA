/// Pure classifiers for chat generation errors.
///
/// Moved verbatim out of `_ChatScreenState` (`lib/presentation/chats/chats.dart`)
/// so the string→string mapping is unit-testable without widgets.
/// Brand copy was normalized to "AgentA" in F23 — display-only
/// strings; if you reword them, keep the normalized brand and update the
/// `test/chat_error_classifier_test.dart` assertions.
///
/// cycle-36 P3 added the OpenRouter branch table (contracts/openrouter-ai.yaml
/// §3): the exact-match rows run before the broad `openrouter` fallback, and
/// both run before the generic api-error catch-all, so a quota or
/// configuration error is never masked as "failed to respond".
///
/// cycle-37 P3 (contract v1.1.0 §3 branch_table) re-orders that table: the
/// four CLASSIFIED rows come first — harness-gate, budget/key-limit,
/// moderation/safety-layer, permission — so a 403 is never described with
/// the retired generic decline copy. The match keys are substrings of the
/// contract's `service_message` strings, which the service throws after
/// parsing the provider's error body.
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
    // OpenRouter branches (contract §3 branch_table) — the four CLASSIFIED
    // rows first (harness-gate → budget → moderation → permission), then the
    // exact rows (key-not-configured / rate limit / free quota), then the
    // broad fallback; all of them before the generic catch-all below, so a
    // classified error is never masked.
    if (lower.contains('restricted to agentic harnesses')) {
      return "This model is restricted by its provider to certain AI tools on OpenRouter's free tier. Please pick another model.";
    }
    if (lower.contains('openrouter key spending limit')) {
      return "Your OpenRouter key has reached its spending limit. Raise or remove the key's limit in the OpenRouter dashboard, then try again.";
    }
    if (lower.contains('openrouter blocked this request')) {
      return "The AI service declined this request: the provider's safety layer blocked it. Please try again or switch models.";
    }
    if (lower.contains('openrouter refused the request')) {
      return "Your OpenRouter account or API key is restricted from this request. Check your OpenRouter account settings or switch models.";
    }
    if (lower.contains('openrouter api key not configured')) {
      return 'Chat service is not configured correctly.';
    }
    if (lower.contains('openrouter rate limit')) {
      return 'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.';
    }
    if (lower.contains('openrouter free quota')) {
      return 'Free chat quota reached for today. Try again tomorrow or switch models.';
    }
    if (lower.contains('openrouter')) {
      return _openRouterFriendly(lower);
    }
    if (lower.contains('api error') || lower.contains('service error')) {
      return 'The selected AI model failed to respond. Please try again.';
    }

    return 'The selected AI model failed to respond. Please try again.';
  }

  /// The broad `openrouter` branch of the contract's branch table, resolved
  /// against the contract's error table (contracts/openrouter-ai.yaml §1):
  /// every OpenRouter status maps to its own friendly copy instead of a
  /// single catch-all string. The 5xx case (and anything unknown) is the
  /// branch table's default copy.
  ///
  /// The generic decline row (`declined` / `rejected the request`) is
  /// RETIRED (contract §3 retired_rows): the four classified rows resolve
  /// every 403 before any generic path, and no amended `service_message`
  /// contains either substring — so the old misleading copy can never
  /// preempt a classified row.
  static String _openRouterFriendly(String lower) {
    if (lower.contains('invalid openrouter api key')) {
      return 'Chat service is not configured correctly.';
    }
    if (lower.contains('free quota')) {
      return 'Free chat quota reached for today. Try again tomorrow or switch models.';
    }
    if (lower.contains('rate limit')) {
      return 'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'Connection timed out. Check your internet connection.';
    }
    if (lower.contains('full response budget')) {
      return 'The model used its full response budget. Please try again.';
    }
    if (lower.contains('request error')) {
      return 'The selected AI model failed to respond. Please try again.';
    }
    return 'The AI service is temporarily unavailable. Please try again.';
  }
}
