import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiteRT-LM engine registration (cycle-38 P2)', () {
    test('the engine claims .litertlm specs and refuses .task specs', () {
      const engine = LiteRtLmEngine();
      expect(
        engine.canHandle(
          InferenceModelSpec(
            name: 'gemma-4-E2B-it.litertlm',
            modelSource: FileSource('/tmp/gemma-4-E2B-it.litertlm'),
            modelType: ModelType.gemma4,
            fileType: ModelFileType.litertlm,
          ),
        ),
        isTrue,
      );
      expect(
        engine.canHandle(
          InferenceModelSpec(
            name: 'gemma3-1b-it-int4.task',
            modelSource: FileSource('/tmp/gemma3-1b-it-int4.task'),
            modelType: ModelType.gemmaIt,
            fileType: ModelFileType.task,
          ),
        ),
        isFalse,
      );
    });

    test('main.dart registers LiteRT-LM alongside MediaPipe', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains(
          "import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';",
        ),
      );
      expect(
        source,
        contains(
          'inferenceEngines: const [MediaPipeEngine(), LiteRtLmEngine()]',
        ),
      );
    });

    test('the pubspec pins litertlm 1.8.6 exactly (core pairing)', () {
      final source = File('pubspec.yaml').readAsStringSync();
      expect(source, contains('flutter_edge_ai_litertlm: 1.8.6'));
      expect(source, isNot(contains('flutter_edge_ai_litertlm: ^')));
      // The core + mediapipe pins stay untouched (litertlm 1.8.7+ demands
      // core ^2.x).
      expect(source, contains('flutter_edge_ai: ^1.11.4'));
      expect(source, contains('flutter_edge_ai_mediapipe: ^1.0.8'));
    });

    test('the lockfile keeps the core + mediapipe pins unchanged', () {
      final lock = File('pubspec.lock').readAsStringSync();
      String lockedVersion(String pkg) {
        final match = RegExp(
          RegExp.escape(pkg) + r':[\s\S]*?version: "([^"]+)"',
        ).firstMatch(lock);
        return match?.group(1) ?? '';
      }

      expect(lockedVersion('flutter_edge_ai'), '1.11.4');
      expect(lockedVersion('flutter_edge_ai_mediapipe'), '1.0.8');
      expect(lockedVersion('flutter_edge_ai_litertlm'), '1.8.6');
    });
  });
}
