import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:aiproject/core/utils/ai_output_guard.dart';

/// The exact artifact observed on the user's device (cycle-23 bug report).
const String goldenArtifact =
    '[Your message here. Remember to keep it in English, even if the '
    "user's message is in another language.]";

const String goldenAnswer = 'Absolutely — here is a short plan for your week.';

const String goldenLeak = '$goldenAnswer\n\n$goldenArtifact';

/// The golden leak split across six stream chunks (artifact spans chunks).
final List<String> goldenChunks = <String>[
  'Absolutely — here is ',
  'a short plan',
  ' for your week.\n\n[Your ',
  'message here. Remember to keep ',
  "it in English, even if the user's ",
  'message is in another language.]',
];

void main() {
  group('AiOutputGuard.stripPromptArtifacts', () {
    test('strips the golden leak artifact (trailing)', () {
      expect(AiOutputGuard.stripPromptArtifacts(goldenLeak), goldenAnswer);
    });

    test('strips the golden leak with trailing whitespace after it', () {
      expect(AiOutputGuard.stripPromptArtifacts('$goldenLeak\n'), goldenAnswer);
    });

    test('leaves a clean response byte-identical', () {
      const clean = 'Paris is the capital of France.';
      expect(AiOutputGuard.stripPromptArtifacts(clean), clean);
    });

    test('leaves a trailing Markdown link untouched', () {
      const text =
          'For details see the [Flutter docs](https://docs.flutter.dev).';
      expect(AiOutputGuard.stripPromptArtifacts(text), text);
    });

    test('leaves a plain trailing bracket untouched', () {
      const text = 'Take the optional [premium plan]';
      expect(AiOutputGuard.stripPromptArtifacts(text), text);
    });

    test('leaves a single weak marker untouched', () {
      const text = 'Checklist:\n[Remember to save your work]';
      expect(AiOutputGuard.stripPromptArtifacts(text), text);
    });

    test('leaves a single non-anchor marker untouched', () {
      const text = 'Format: [Respond ONLY in French]';
      expect(AiOutputGuard.stripPromptArtifacts(text), text);
    });

    test('leaves a mid-text artifact untouched (out of scope by design)', () {
      const text = 'Use this format: [Your message here] — then replace it.';
      expect(AiOutputGuard.stripPromptArtifacts(text), text);
    });

    test('strips when two markers co-occur without the anchor', () {
      const text = 'Note:\n[Keep it in English, even in another language]';
      expect(AiOutputGuard.stripPromptArtifacts(text), 'Note:');
    });

    test('matches markers case-insensitively and across line wraps', () {
      const upperAnchor = 'Hi\n[YOUR MESSAGE HERE]';
      expect(AiOutputGuard.stripPromptArtifacts(upperAnchor), 'Hi');

      const wrapped = 'Note:\n[keep it in\nEnglish, even in another language]';
      expect(AiOutputGuard.stripPromptArtifacts(wrapped), 'Note:');
    });

    test('strips a pure-artifact response to empty (degenerate, recorded)', () {
      expect(AiOutputGuard.stripPromptArtifacts('[Your message here.]'), '');
    });
  });

  group('AiOutputGuard.guardStream', () {
    test(
      'withholds a split golden artifact and equals strip(full text)',
      () async {
        final emitted = <String>[];
        await for (final chunk in AiOutputGuard.guardStream(
          Stream.fromIterable(goldenChunks),
        )) {
          emitted.add(chunk);
        }

        // Invariant: stream output == strip of the full response, byte-exact.
        expect(
          emitted.join(),
          AiOutputGuard.stripPromptArtifacts(goldenChunks.join()),
        );
        expect(emitted.join(), goldenAnswer);

        // The artifact never reaches a consumer, not even partially.
        for (final chunk in emitted) {
          expect(chunk.toLowerCase().contains('message here'), isFalse);
          expect(chunk.contains('['), isFalse);
        }
      },
    );

    test('passes a clean response through byte-identical', () async {
      const chunks = ['Paris ', 'is the ', 'capital of France.'];
      final emitted = await AiOutputGuard.guardStream(
        Stream.fromIterable(chunks),
      ).toList();
      expect(emitted.join(), chunks.join());
    });

    test('passes a trailing Markdown link through byte-identical', () async {
      final chunks = ['See ', '[Flutter ', 'docs](https://docs.flutter.dev).'];
      final emitted = await AiOutputGuard.guardStream(
        Stream.fromIterable(chunks),
      ).toList();
      expect(emitted.join(), chunks.join());
      expect(emitted.join(), 'See [Flutter docs](https://docs.flutter.dev).');
    });

    test('propagates stream errors and drops the withheld tail', () async {
      Stream<String> failing() async* {
        yield 'Partial answer ';
        throw const FormatException('boom');
      }

      final emitted = <String>[];
      try {
        await for (final chunk in AiOutputGuard.guardStream(failing())) {
          emitted.add(chunk);
        }
        fail('expected the stream to throw');
      } on FormatException catch (error) {
        expect(error.message, 'boom');
      }

      // The safe prefix was emitted; the withheld whitespace tail is dropped.
      expect(emitted.join(), 'Partial answer');
    });

    test('cancellation stops emission and drops the withheld tail', () async {
      final controller = StreamController<String>();
      final emitted = <String>[];
      final subscription = AiOutputGuard.guardStream(
        controller.stream,
      ).listen(emitted.add);

      controller.add('Hello ');
      await pumpEventQueue();
      await subscription.cancel();

      controller.add('[Your message here.]');
      await pumpEventQueue();

      expect(emitted.join(), 'Hello');
      unawaited(controller.close());
    });
  });
}
