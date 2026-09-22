import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/services/ai/model_download_service.dart';

void main() {
  late ModelDownloadService service;

  setUp(() {
    service = ModelDownloadService();
  });

  group('ModelDownloadService.friendlyDownloadError', () {
    test('maps every DownloadError subtype to its friendly state', () {
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.notFound())),
        'The offline model file could not be found at its source. '
        'Check the download link.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.unauthorized())),
        'The model source rejected the download.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.forbidden())),
        'The model source rejected the download.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.rateLimited())),
        'Too many download attempts. Try again later.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.network('reset'))),
        'No internet connection. Download will resume when you are back online.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.serverError(503))),
        'Download failed. Please try again.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.unknown('weird'))),
        'Download failed. Please try again.',
      );
    });

    test('cancellation stays silent (null)', () {
      expect(
        service.friendlyDownloadErrorForTest(
            const DownloadException(DownloadError.canceled())),
        isNull,
      );
    });

    test('timeout and unknown failures get generic friendly states', () {
      expect(
        service.friendlyDownloadErrorForTest(
            TimeoutException('install', const Duration(minutes: 30))),
        'Download timed out. Please try again.',
      );
      expect(
        service.friendlyDownloadErrorForTest(Exception('boom')),
        'Download failed. Please try again.',
      );
    });

    test('friendly states stay brand-free and leak no raw detail', () {
      const errors = [
        DownloadError.notFound(),
        DownloadError.unauthorized(),
        DownloadError.forbidden(),
        DownloadError.rateLimited(),
        DownloadError.network('ECONNRESET by 1.2.3.4 (null socket)'),
        DownloadError.serverError(500),
        DownloadError.unknown('原始错误 gemma3-1b-it-int4.task hf_token=abc'),
      ];
      const banned = [
        'gemma',
        '.task',
        'huggingface',
        'hf_',
        'http',
        '401',
        '403',
        '404',
        '429',
        '500',
        'null',
        'econnreset',
        '1.2.3.4',
        'abc',
      ];
      for (final error in errors) {
        final message =
            service.friendlyDownloadErrorForTest(DownloadException(error));
        expect(message, isNotNull, reason: '$error');
        final lower = message!.toLowerCase();
        for (final token in banned) {
          expect(lower.contains(token), isFalse,
              reason: 'message "$message" leaks "$token"');
        }
      }
    });
  });

  group('ModelDownloadService.applyDownloadFailure', () {
    test('cancellation resets to a neutral, silent state', () {
      service.applyDownloadFailureForTest(
        const DownloadException(DownloadError.canceled()),
        'test',
      );
      expect(service.status, ModelStatus.notInstalled);
      expect(service.errorMessage, isNull);
      expect(service.progress, 0.0);
    });

    // Error branches also write the friendly message to the DAO (sqflite),
    // which needs a device plugin — not feasible in VM unit tests without a
    // sqflite channel-mock harness. Covered instead by the pure mapper tests
    // above plus manual device verification.
  });
}
