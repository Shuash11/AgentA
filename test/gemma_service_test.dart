import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/data/models/chat_message_model.dart';
import 'package:aiproject/services/ai/gemma_service.dart';

ChatMessageModel _msg(String text, {bool isUser = true, String id = 'm'}) {
  return ChatMessageModel(
    id: id,
    chatId: 'c',
    text: text,
    isUser: isUser,
    timestamp: DateTime(2026, 1, 1),
  );
}

void main() {
  late GemmaService service;

  setUp(() {
    service = GemmaService();
  });

  group('GemmaService.truncateAtSentence', () {
    test('cuts at the last period boundary before the limit', () {
      const text = 'First sentence. Second sentence here and more';
      expect(service.truncateAtSentenceForTest(text, 30), 'First sentence.…');
    });

    test('prefers the latest boundary, not the first', () {
      const text = 'One. Two. Three and more words here';
      expect(service.truncateAtSentenceForTest(text, 22), 'One. Two.…');
    });

    test('cuts at question and exclamation boundaries', () {
      expect(
        service.truncateAtSentenceForTest('Really? Yes indeed and more', 20),
        'Really?…',
      );
      expect(
        service.truncateAtSentenceForTest('Wow! Amazing stuff here now', 12),
        'Wow!…',
      );
    });

    test('cuts at newline boundaries', () {
      expect(
        service.truncateAtSentenceForTest('Line one\nLine two continues', 15),
        'Line one…',
      );
    });

    test('falls back to a word boundary without sentence markers', () {
      expect(
        service.truncateAtSentenceForTest('aaa bbb ccc ddd eee fff', 10),
        'aaa bbb…',
      );
    });

    test('hard-cuts text with no spaces at all', () {
      expect(
        service.truncateAtSentenceForTest('abcdefghijklmnop', 6),
        'abcdef…',
      );
    });
  });

  group('GemmaService.classifyLoadError', () {
    test('maps missing-model signals to not-installed', () {
      expect(
        service.classifyLoadErrorForTest(
          StateError('Bad state: No active model'),
          false,
        ),
        'Offline model is not installed.',
      );
      expect(
        service.classifyLoadErrorForTest(
          Exception('model not installed'),
          false,
        ),
        'Offline model is not installed.',
      );
      expect(
        service.classifyLoadErrorForTest(
          Exception('No such file or directory'),
          false,
        ),
        'Offline model is not installed.',
      );
      expect(
        service.classifyLoadErrorForTest(Exception('404 not found'), false),
        'Offline model is not installed.',
      );
    });

    test('failed rehydration means not-installed regardless of text', () {
      expect(
        service.classifyLoadErrorForTest(Exception('boom'), true),
        'Offline model is not installed.',
      );
    });

    test('null-mentioning errors are NOT misclassified as not-installed', () {
      // Phase 2 regression lock: the old raw.contains('null') branch is gone.
      expect(
        service.classifyLoadErrorForTest(
          Exception('Null check operator used on a null value'),
          false,
        ),
        'Offline model failed to load.',
      );
    });

    test('generic failures map to failed-to-load', () {
      expect(
        service.classifyLoadErrorForTest(Exception('boom'), false),
        'Offline model failed to load.',
      );
    });

    test('typed download errors fall through to failed-to-load here', () {
      // Download UX is owned by ModelDownloadService's typed mapping;
      // this classifier only handles non-download load failures.
      const typed = DownloadException(
        DownloadError.network('connection reset'),
      );
      expect(
        service.classifyLoadErrorForTest(typed, false),
        'Offline model failed to load.',
      );
    });
  });

  group('GemmaService.endsAtNaturalBreak', () {
    test('punctuation endings break', () {
      for (final token in ['hello.', 'a,', 'x:', 'y;', 'wow!', 'really?']) {
        expect(service.endsAtNaturalBreakForTest(token), isTrue, reason: token);
      }
      // A trailing newline still flushes when punctuation precedes it —
      // trimRight runs first, so the '.' decides here.
      expect(service.endsAtNaturalBreakForTest('word.\n'), isTrue);
    });

    test('mid-word tokens do not break', () {
      expect(service.endsAtNaturalBreakForTest('abc'), isFalse);
      expect(service.endsAtNaturalBreakForTest('word '), isFalse);
      expect(service.endsAtNaturalBreakForTest(''), isFalse);
      expect(service.endsAtNaturalBreakForTest('   '), isFalse);
      // trimRight strips trailing newlines before the check, so a bare
      // newline never breaks on its own (the '\n' arm is inert).
      expect(service.endsAtNaturalBreakForTest('line\n'), isFalse);
      expect(service.endsAtNaturalBreakForTest('\n'), isFalse);
    });
  });

  group('GemmaService.recentHistory', () {
    test('empty history stays empty', () {
      expect(service.recentHistoryForTest([], currentMessage: 'hi'), isEmpty);
    });

    test('filters the greeting and blank messages', () {
      final history = [
        _msg(GemmaService.greetingText, id: 'g'),
        _msg('   ', id: 'b'),
        _msg('real question', id: 'r'),
      ];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'next',
      );
      expect(recent.map((m) => m.id), ['r']);
    });

    test('removes a trailing duplicate of the new user message', () {
      final history = [_msg('hi', id: 'a'), _msg('current', id: 'dup')];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'current',
      );
      expect(recent.map((m) => m.id), ['a']);
    });

    test('keeps a same-text trailing assistant message', () {
      final history = [_msg('current', isUser: false, id: 'asst')];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'current',
      );
      expect(recent.map((m) => m.id), ['asst']);
    });

    test('caps history at the most recent messages', () {
      final history = [for (var i = 0; i < 10; i++) _msg('msg $i', id: 'm$i')];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'new',
      );
      expect(recent, hasLength(8));
      expect(recent.first.id, 'm2');
      expect(recent.last.id, 'm9');
    });

    test('truncates over-cap messages at a sentence boundary', () {
      final longText = '${'Sentence one. ' * 100}tail without end';
      final history = [_msg(longText, id: 'long', isUser: false)];
      final recent = service.recentHistoryForTest(
        history,
        currentMessage: 'new',
      );
      expect(recent, hasLength(1));
      final truncated = recent.first;
      expect(truncated.text.endsWith('…'), isTrue);
      expect(truncated.text.length, lessThan(longText.length));
      expect(truncated.text, startsWith('Sentence one.'));
      // Identity fields survive truncation.
      expect(truncated.id, 'long');
      expect(truncated.chatId, 'c');
      expect(truncated.isUser, isFalse);
    });
  });
}
