// Model registry for the chat picker.
//
// cycle-36 P3: two free OpenRouter cloud models were added. The enum NAME is
// part of the contract (contracts/openrouter-ai.yaml §3): the image-model
// heuristic in chats.dart / model_picker_sheet.dart detects image models by
// the substring "pollinations" or "image", so neither new value may contain
// either substring.
enum AIModel { pollinations, groq, openrouterFlash, openrouterPro, gemma }

/// The reasoning-effort tiers the app offers (contracts/openrouter-ai.yaml
/// v1.3.0 §3 reasoning-effort state — the tier enum).
///
/// `auto` expresses NO effort preference — the request omits the effort key
/// so the model/provider default applies (on Pro that default is `high`).
/// The remaining tiers are real API effort values; `maximum` maps to the
/// documented `"max"` value on the wire.
enum ReasoningEffortTier {
  auto,
  low,
  medium,
  high,
  maximum;

  /// Parses a persisted tier name. An absent, empty or unknown value falls
  /// back to [auto] — the contract default — so a corrupt preference can
  /// never produce a bogus tier.
  static ReasoningEffortTier fromName(String? name) {
    for (final tier in values) {
      if (tier.name == name) return tier;
    }
    return auto;
  }
}

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
        return 'Smarter offline AI — ~1.6GB download, runs on your device';
    }
  }

  bool get isImageGeneration => this == AIModel.pollinations;

  /// The reasoning-effort tiers this model accepts (contracts/openrouter-ai.yaml
  /// v1.3.0 §1 reasoning-effort capability — the source of truth for code).
  ///
  /// An EMPTY set means the model has no reasoning-effort surface at all:
  /// Groq and Pollinations carry no reasoning object on their request shapes
  /// and the offline model has no thinking control at the current engine
  /// pins — nothing is ever sent on those paths (contract §4.9).
  ///
  /// Pro publishes only `auto`, `medium` and `high`; `low` and `maximum` are
  /// NOT published for it and are never sent, never silently mapped. Flash's
  /// full set is live-proof-gated (the plan's live-proof phase).
  Set<ReasoningEffortTier> get supportedReasoningTiers {
    switch (this) {
      case AIModel.openrouterFlash:
        return const {
          ReasoningEffortTier.auto,
          ReasoningEffortTier.low,
          ReasoningEffortTier.medium,
          ReasoningEffortTier.high,
          ReasoningEffortTier.maximum,
        };
      case AIModel.openrouterPro:
        return const {
          ReasoningEffortTier.auto,
          ReasoningEffortTier.medium,
          ReasoningEffortTier.high,
        };
      case AIModel.pollinations:
      case AIModel.groq:
      case AIModel.gemma:
        return const {};
    }
  }

  /// True iff the model exposes a reasoning-effort control at all.
  bool get supportsReasoningEffort => supportedReasoningTiers.isNotEmpty;
}
