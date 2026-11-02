import '../../data/models/chat_message_model.dart';

/// Builds the ROLE-MARKED priming chunk of one send (cycle-45 Phase 1).
///
/// WHY THIS EXISTS — the defect it fixes
/// -------------------------------------
/// The `.task` engine boundary strips every role marker: the pinned plugin's
/// `_chatFormatModeFor` returns `raw` for `ModelFileType.task`
/// (`flutter_edge_ai-1.11.4` core `extensions.dart:57-69`) and
/// `_formatToolResponseContent` returns the plain text (`:135-143`), so the
/// `isUser` flag NEVER reaches the prompt. Every staged chunk also lands in
/// ONE native buffer — the MediaPipe session hands each chunk to the native
/// session as-is (`flutter_edge_ai_mediapipe-1.0.8`
/// `mobile_inference_session.dart:112` → `MediaPipeSession.kt:60-62`), and
/// the litertlm sibling shows the same concatenation semantics in Dart
/// (`_queryBuffer.write(prompt)`, `flutter_edge_ai_litertlm-1.8.6`
/// `ffi_inference_model.dart:408-414`). So the prior turns + the new message
/// reached Qwen2.5-1.5B as ONE role-less user string — the 1.5B
/// pattern-completed it to the canned greeting instead of recalling the name.
///
/// The fix is app-side TEXT: every prior turn is rendered with an explicit
/// role label ("User: …" / "Assistant: …"), which is the only structure the
/// RAW boundary can carry. The labels make the turn structure visible to the
/// model even though the engine sees a single user turn.
///
/// THE BUDGET (the S3 ruling — the binding rule)
/// ---------------------------------------------
/// The TOTAL staged text of one send — the priming text PLUS the new message
/// — stays at or below [defaultMaxStagedChars] (5000 chars ≈ 1250 estimated
/// tokens at the ruled chars/4 estimator). The 8-message and 1000-char
/// per-message caps stay SECONDARY bounds (they are applied upstream by
/// `GemmaService._getRecentHistory`); the total budget is what binds.
///
/// The fill is NEWEST-FIRST: the turns are collected from the newest
/// backwards and the OLDEST are dropped until the whole set fits — a turn is
/// never split, never truncated, and never left with a dangling role label.
/// The new message is never truncated: when it alone exceeds the budget the
/// priming is empty and the message still goes out intact.
class TurnPrimingBuilder {
  /// The estimator the S3 ruling counts with: ~4 characters per token.
  static const int charsPerToken = 4;

  /// The TOTAL staged budget in estimated tokens (S3): 1250.
  static const int defaultMaxStagedTokens = 1250;

  /// The TOTAL staged budget in characters (S3): 5000. The binding rule is
  /// `priming text + new message ≤ 5000 chars`.
  static const int defaultMaxStagedChars =
      defaultMaxStagedTokens * charsPerToken;

  /// The role label of a user turn — the app-side stand-in for the role
  /// marker the RAW boundary strips.
  static const String userLabel = 'User:';

  /// The role label of an assistant turn.
  static const String assistantLabel = 'Assistant:';

  /// The separator between two role-marked turns. The same separator trails
  /// the priming text so the new-message chunk — staged as the NEXT chunk —
  /// starts on its own line instead of running into the last turn.
  static const String turnSeparator = '\n\n';

  /// A builder that spends at most [maxStagedChars] on the priming text.
  const TurnPrimingBuilder({this.maxStagedChars = defaultMaxStagedChars});

  /// The TOTAL staged-char budget: the priming text PLUS the new message.
  final int maxStagedChars;

  /// The role-marked priming text for [recentHistory].
  ///
  /// [recentHistory] is the ALREADY de-duped and capped window
  /// (`GemmaService._getRecentHistory` runs both de-dup rules upstream); this
  /// builder adds the role marking and the total-budget fit.
  ///
  /// [stagedNewMessageLength] is the length of the new message AS STAGED
  /// (trimmed) — it is part of the same budget and is never truncated.
  String build(
    List<ChatMessageModel> recentHistory, {
    required int stagedNewMessageLength,
  }) {
    final primingBudget = maxStagedChars - stagedNewMessageLength;
    if (primingBudget <= 0) return '';

    // Newest-first: collect from the newest turn backwards and stop at the
    // first turn that does not fit — the OLDEST turns are the ones dropped.
    final blocks = <String>[];
    var chars = 0;
    for (final message in recentHistory.reversed) {
      final block = _roleBlock(message);
      if (block == null) continue;
      // Each block costs its own text plus one separator; the trailing
      // separator of the last block is the same cost, so the running total is
      // the exact length of the rendered text.
      final candidateChars = chars + block.length + turnSeparator.length;
      if (candidateChars > primingBudget) break;
      blocks.insert(0, block);
      chars = candidateChars;
    }
    if (blocks.isEmpty) return '';
    return blocks.join(turnSeparator) + turnSeparator;
  }

  /// One role-marked turn, or null when the turn carries no text (an empty
  /// turn would leave a dangling role label — never rendered).
  String? _roleBlock(ChatMessageModel message) {
    final text = message.text.trim();
    if (text.isEmpty) return null;
    final label = message.isUser ? userLabel : assistantLabel;
    return '$label $text';
  }
}
