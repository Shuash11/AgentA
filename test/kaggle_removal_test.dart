import 'dart:io';

import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the dead Kaggle fallback removal.
///
/// The Kaggle path (KaggleDownloadService, installModelFromKaggle,
/// canUseKaggle, config getters) was deleted in Phase 1 and its CI secrets
/// in Phase 2. This test fails if any of it creeps back into lib/.
/// A CI grep guard in build-apk.yml enforces the same rule on every build.
void main() {
  group('Kaggle removal regression guard', () {
    test('lib sources contain no kaggle references', () {
      final root = _findRepoRoot();
      const watched = [
        'lib/services/ai/model_download_service.dart',
        'lib/presentation/ai/download_prompt_screen.dart',
        'lib/core/config/app_config.dart',
      ];

      for (final relative in watched) {
        final file = File('${root.path}/$relative');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'expected source file missing: $relative '
              '(repo root resolved as ${root.path})',
        );
        final content = file.readAsStringSync();
        expect(
          content.toLowerCase().contains('kaggle'),
          isFalse,
          reason: '$relative mentions kaggle',
        );
      }
    });

    test('removed Kaggle API surface stays gone', () {
      final root = _findRepoRoot();
      final sources = [
        File(
          '${root.path}/lib/services/ai/model_download_service.dart',
        ).readAsStringSync(),
        File('${root.path}/lib/core/config/app_config.dart').readAsStringSync(),
      ].join('\n');

      for (final token in [
        'canUseKaggle',
        'installModelFromKaggle',
        'KaggleDownloadService',
      ]) {
        expect(
          sources.contains(token),
          isFalse,
          reason: 'removed API resurfaced: $token',
        );
      }
    });

    test('installModel path stays intact', () {
      final service = ModelDownloadService();
      // Method tear-off proves the install entry point still exists.
      expect(service.installModel, isA<Function>());
      expect(service.status, ModelStatus.notInstalled);
      expect(service.progress, 0.0);
      expect(service.errorMessage, isNull);
    });
  });
}

/// Resolves the package root by walking up from [Directory.current] until
/// pubspec.yaml is found. `flutter test` runs with the package root as the
/// working directory, so this is normally a single step; the walk keeps the
/// guard robust when tests run from a nested cwd.
Directory _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current;
}
