import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_llama/flutter_edge_ai_llama.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('llama.cpp engine registration (C46 P2)', () {
    test('the engine claims .gguf specs and refuses .task specs', () {
      const engine = LlamaEngineProvider();
      // The llama engine claims the GGUF TYPE — it stays registered after
      // the cycle-46 revert (idle while no GGUF spec is selected, and the
      // ladder's light-quant experiment would claim it again).
      expect(
        engine.canHandle(
          InferenceModelSpec(
            name: 'MiniCPM5-2B-Q4_K_M.gguf',
            modelSource: FileSource('/tmp/MiniCPM5-2B-Q4_K_M.gguf'),
            modelType: ModelType.llama,
            fileType: ModelFileType.gguf,
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

    test('main.dart registers the llama engine alongside MediaPipe', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains(
          "import 'package:flutter_edge_ai_llama/flutter_edge_ai_llama.dart';",
        ),
      );
      expect(
        source,
        contains(
          'inferenceEngines: const [MediaPipeEngine(), LlamaEngineProvider()]',
        ),
      );
    });

    test('the pubspec carries the core-2.x cascade and no litertlm', () {
      final source = File('pubspec.yaml').readAsStringSync();
      expect(source, contains('flutter_edge_ai: ^2.5.5'));
      expect(source, contains('flutter_edge_ai_mediapipe: ^1.2.5'));
      expect(source, contains('flutter_edge_ai_llama: ^0.0.5'));
      expect(source, isNot(contains('flutter_edge_ai_litertlm')));
    });

    test('the lockfile resolves the cascade', () {
      final lock = File('pubspec.lock').readAsStringSync();
      String lockedVersion(String pkg) {
        final match = RegExp(
          RegExp.escape(pkg) + r':[\s\S]*?version: "([^"]+)"',
        ).firstMatch(lock);
        return match?.group(1) ?? '';
      }

      expect(lockedVersion('flutter_edge_ai'), '2.5.5');
      expect(lockedVersion('flutter_edge_ai_mediapipe'), '1.2.5');
      expect(lockedVersion('flutter_edge_ai_llama'), '0.0.5');
      expect(lock, isNot(contains('flutter_edge_ai_litertlm')));
    });
  });
}
