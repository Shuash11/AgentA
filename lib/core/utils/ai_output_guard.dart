import 'dart:async';

/// Output-hygiene guard for AI chat responses (F29).
///
/// Small models (allam-2-7b online, Gemma offline) sometimes echo
/// prompt-scaffolding, e.g. a trailing bracketed template placeholder such
/// as `[Your message here. Remember to keep it in English, ...]`. This
/// guard removes that observed class at the AI-service output boundary and
/// never touches legitimate bracketed content (Markdown links, inline
/// brackets, ordinary prose).
///
/// Two entry points:
/// - [stripPromptArtifacts] cleans a completed response string.
/// - [guardStream] guards a token stream with a holdback buffer so the
///   removable tail is never emitted to the UI at all.
class AiOutputGuard {
  const AiOutputGuard._();

  /// Prompt-meta phrases from the observed artifact class, lowercased.
  static const List<String> _markers = [
    'your message here',
    'keep it in english',
    'another language',
    'respond only',
    'remember to',
  ];

  /// Placeholder-syntax anchor: sufficient on its own. The other markers
  /// are ordinary English in isolation and require co-occurrence.
  static const String _anchor = 'your message here';

  /// A trailing bracketed segment: no inner brackets, whitespace-only after.
  static final RegExp _trailingBracket = RegExp(r'\[([^\[\]]*)\]\s*$');

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  static final RegExp _whitespaceChar = RegExp(r'\s');

  /// Strips a trailing prompt-meta artifact from [text].
  ///
  /// Only a trailing, bracketed segment whose content matches the
  /// prompt-meta predicate is removed; anything else is returned
  /// byte-identical.
  static String stripPromptArtifacts(String text) {
    final match = _trailingBracket.firstMatch(text);
    if (match == null || !_isPromptMeta(match.group(1)!)) {
      return text;
    }
    return text.substring(0, match.start).trimRight();
  }

  /// Wraps [source] so the strip-removable tail is withheld until the
  /// stream proves it safe to emit or completes.
  ///
  /// Invariant: the concatenation of emitted chunks equals
  /// [stripPromptArtifacts] applied to the full source text (byte-exact);
  /// a response that strips to empty emits nothing. Cancellation drops the
  /// withheld tail; errors propagate unchanged. Built on a transformer
  /// (not `async*` + `await for`) so cancellation stays prompt — an
  /// `async*` generator parked on an open source does not complete its
  /// cancel future.
  static Stream<String> guardStream(Stream<String> source) {
    var pending = '';
    return source.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (chunk, sink) {
          pending += chunk;
          final holdFrom = _holdStart(pending);
          if (holdFrom > 0) {
            sink.add(pending.substring(0, holdFrom));
            pending = pending.substring(holdFrom);
          }
          // holdFrom == 0: withhold everything until the tail resolves.
        },
        handleError: (error, stackTrace, sink) =>
            sink.addError(error, stackTrace),
        handleDone: (sink) {
          if (pending.isNotEmpty) {
            final stripped = stripPromptArtifacts(pending);
            if (stripped.isNotEmpty) sink.add(stripped);
            pending = '';
          }
          sink.close();
        },
      ),
    );
  }

  /// Index from which [text] must be withheld; `text.length` when the whole
  /// text is provably safe to emit.
  ///
  /// Withheld regions are exactly the suffix candidates the trailing strip
  /// could remove, plus an immediately preceding whitespace run (keeps
  /// end-of-stream stripping byte-exact): an unmatched `[` tail, a closed
  /// marker-matching trailing bracket, or a still-arriving whitespace run
  /// (which may precede an artifact whose `[` has not arrived yet).
  static int _holdStart(String text) {
    final open = text.lastIndexOf('[');
    if (open >= 0 && open > text.lastIndexOf(']')) {
      return _includePrecedingWhitespace(text, open);
    }
    final match = _trailingBracket.firstMatch(text);
    if (match != null && _isPromptMeta(match.group(1)!)) {
      return _includePrecedingWhitespace(text, match.start);
    }
    return _includePrecedingWhitespace(text, text.length);
  }

  static int _includePrecedingWhitespace(String text, int index) {
    var start = index;
    while (start > 0 && _whitespaceChar.hasMatch(text[start - 1])) {
      start--;
    }
    return start;
  }

  static bool _isPromptMeta(String content) {
    final normalized = content.toLowerCase().replaceAll(_whitespaceRun, ' ');
    if (normalized.contains(_anchor)) return true;
    return _markers.where((marker) => normalized.contains(marker)).length >= 2;
  }
}
