import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/core/config/app_config.dart';
import 'package:aiproject/data/local/database_helper.dart';
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
          const DownloadException(DownloadError.notFound()),
        ),
        'The offline model file could not be found at its source. '
        'Check the download link.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.unauthorized()),
        ),
        'The model source rejected the download.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.forbidden()),
        ),
        'The model source rejected the download.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.rateLimited()),
        ),
        'Too many download attempts. Try again later.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.network('reset')),
        ),
        'No internet connection. Download will resume when you are back online.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.serverError(503)),
        ),
        'Download failed. Please try again.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.unknown('weird')),
        ),
        'Download failed. Please try again.',
      );
    });

    test('cancellation stays silent (null)', () {
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.canceled()),
        ),
        isNull,
      );
    });

    test('timeout and unknown failures get generic friendly states', () {
      expect(
        service.friendlyDownloadErrorForTest(
          TimeoutException('install', const Duration(minutes: 30)),
        ),
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
        final message = service.friendlyDownloadErrorForTest(
          DownloadException(error),
        );
        expect(message, isNotNull, reason: '$error');
        final lower = message!.toLowerCase();
        for (final token in banned) {
          expect(
            lower.contains(token),
            isFalse,
            reason: 'message "$message" leaks "$token"',
          );
        }
      }
    });
  });

  group('ModelDownloadService stall/timeout/cancel mapping', () {
    test('stall maps to a friendly retryable message', () {
      expect(
        service.friendlyDownloadErrorForTest(const DownloadStalledException()),
        'Download stalled. Please try again.',
      );
    });

    test('raw plugin cancellation stays silent (null)', () {
      expect(
        service.friendlyDownloadErrorForTest(
          DownloadCancelledException('User cancelled', StackTrace.empty),
        ),
        isNull,
      );
      expect(
        CancelToken.isCancel(DownloadCancelledException('x', StackTrace.empty)),
        isTrue,
      );
    });

    test('stall/timeout/cancel states stay brand-free', () {
      const banned = [
        'gemma',
        '.task',
        'huggingface',
        'hf_',
        'http',
        'downloadcancelled',
        'downloadstalled',
        'timeoutexception',
      ];
      final messages = [
        service.friendlyDownloadErrorForTest(const DownloadStalledException()),
        service.friendlyDownloadErrorForTest(
          TimeoutException('install', const Duration(minutes: 30)),
        ),
      ];
      for (final message in messages) {
        expect(message, isNotNull);
        final lower = message!.toLowerCase();
        for (final token in banned) {
          // Friendly copy must not leak raw exception detail; the typed
          // toString()s may carry it, the UI strings must not.
          expect(
            lower.contains(token),
            isFalse,
            reason: 'message "$message" leaks "$token"',
          );
        }
      }
    });

    test('fireStallTimeout is a no-op when not installing', () {
      service.fireStallTimeoutForTest();
      expect(service.status, ModelStatus.notInstalled);
      expect(service.stallFiredForTest, isFalse);
      expect(service.hasActiveWatchdogForTest, isFalse);
    });
  });

  group('AppConfig.foregroundDownload', () {
    tearDown(() {
      AppConfig.foregroundDownloadOverrideForTest = null;
    });

    test('parses true/false case-insensitively, default true', () {
      expect(AppConfig.parseForegroundDownloadForTest(''), isTrue);
      expect(AppConfig.parseForegroundDownloadForTest('true'), isTrue);
      expect(AppConfig.parseForegroundDownloadForTest('TRUE'), isTrue);
      expect(AppConfig.parseForegroundDownloadForTest('True'), isTrue);
      expect(AppConfig.parseForegroundDownloadForTest('false'), isFalse);
      expect(AppConfig.parseForegroundDownloadForTest('FALSE'), isFalse);
      expect(AppConfig.parseForegroundDownloadForTest('False'), isFalse);
    });

    test('unrecognised values fall back to true', () {
      expect(AppConfig.parseForegroundDownloadForTest('banana'), isTrue);
      expect(AppConfig.parseForegroundDownloadForTest('0'), isTrue);
      expect(AppConfig.parseForegroundDownloadForTest('  '), isTrue);
    });

    test('defaults to true when the env is unset', () {
      AppConfig.foregroundDownloadOverrideForTest = null;
      expect(AppConfig.foregroundDownload, isTrue);
    });

    test('test override flips the flag both ways', () {
      AppConfig.foregroundDownloadOverrideForTest = false;
      expect(AppConfig.foregroundDownload, isFalse);
      AppConfig.foregroundDownloadOverrideForTest = true;
      expect(AppConfig.foregroundDownload, isTrue);
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

  group('ModelDownloadService wedge-proofing (DB-backed)', () {
    late Database db;

    setUpAll(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE offline_model_status (
                id INTEGER PRIMARY KEY,
                model_type TEXT NOT NULL,
                status TEXT NOT NULL,
                downloaded_at INTEGER,
                file_path TEXT,
                version TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
          },
        ),
      );
      DatabaseHelper.testDatabase = db;
    });

    tearDownAll(() async {
      DatabaseHelper.clearTestDatabase();
      await db.close();
    });

    setUp(() async {
      service = ModelDownloadService();
      await db.delete('offline_model_status');
    });

    tearDown(() {
      service.dispose();
    });

    test('production ceilings: permission 10s, stall 3min, install 30min', () {
      expect(
        ModelDownloadService.permissionTimeoutForTest,
        const Duration(seconds: 10),
      );
      expect(
        ModelDownloadService.stallTimeoutForTest,
        const Duration(minutes: 3),
      );
      expect(
        ModelDownloadService.installTimeoutForTest,
        const Duration(minutes: 30),
      );
      // The stall window must stay above the 60s slow-connection heuristic
      // (a merely slow transfer still emits events and resets the timer).
      expect(
        ModelDownloadService.stallTimeoutForTest,
        greaterThan(const Duration(seconds: 60)),
      );
    });

    test('hanging permission request resolves as denied, quickly', () async {
      service.permissionRequestOverrideForTest = () =>
          Completer<bool?>().future; // never completes
      service.permissionTimeoutOverrideForTest = const Duration(
        milliseconds: 200,
      );
      final watch = Stopwatch()..start();
      final granted = await service.ensureNotificationPermissionForTest();
      watch.stop();
      expect(granted, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('download still starts after the permission request hangs', () async {
      service.permissionRequestOverrideForTest = () =>
          Completer<bool?>().future; // never completes
      service.permissionTimeoutOverrideForTest = const Duration(
        milliseconds: 200,
      );
      var installStarted = false;
      service.installOverrideForTest = (token) async {
        installStarted = true;
      };
      await service.installModel();
      expect(installStarted, isTrue);
      expect(service.status, ModelStatus.ready);
      expect(service.progress, 100.0);
      expect(service.hasActiveWatchdogForTest, isFalse);
    });

    test('watchdog is armed in flight and cleared on success', () async {
      service.permissionTimeoutOverrideForTest = const Duration(
        milliseconds: 50,
      );
      service.stallTimeoutOverrideForTest = const Duration(seconds: 5);
      var armedInFlight = false;
      service.installOverrideForTest = (token) async {
        armedInFlight = service.hasActiveWatchdogForTest;
      };
      await service.installModel();
      expect(armedInFlight, isTrue);
      expect(service.status, ModelStatus.ready);
      expect(service.hasActiveWatchdogForTest, isFalse);
    });

    test(
      'simulated stall surfaces typed error, cancels token, retryable',
      () async {
        service.permissionTimeoutOverrideForTest = const Duration(
          milliseconds: 50,
        );
        service.stallTimeoutOverrideForTest = const Duration(milliseconds: 200);
        CancelToken? captured;
        service.installOverrideForTest = (token) async {
          captured = token;
          // Hang past the watchdog window, then surface the cancellation the
          // plugin raises for the cancelled native task.
          await Future.delayed(const Duration(seconds: 1));
          throw const DownloadException(DownloadError.canceled());
        };
        await service.installModel();
        expect(service.stallFiredForTest, isTrue);
        expect(captured, isNotNull);
        expect(captured!.isCancelled, isTrue);
        expect(service.status, ModelStatus.error);
        expect(service.errorMessage, 'Download stalled. Please try again.');
        expect(service.hasActiveWatchdogForTest, isFalse);

        // Retryable: a fresh attempt proceeds instead of wedging on installing.
        service.installOverrideForTest = (token) async {};
        await service.installModel();
        expect(service.status, ModelStatus.ready);
        expect(service.errorMessage, isNull);
      },
    );

    test(
      '.timeout() path cancels the native task via the CancelToken',
      () async {
        service.permissionTimeoutOverrideForTest = const Duration(
          milliseconds: 50,
        );
        // Keep the watchdog out of the way so only the install ceiling fires.
        service.stallTimeoutOverrideForTest = const Duration(seconds: 30);
        service.installTimeoutOverrideForTest = const Duration(
          milliseconds: 300,
        );
        CancelToken? captured;
        service.installOverrideForTest = (token) async {
          captured = token;
          await Completer<void>().future; // silently-dead native task
        };
        await service.installModel();
        expect(captured, isNotNull);
        expect(captured!.isCancelled, isTrue);
        expect(service.stallFiredForTest, isFalse);
        expect(service.status, ModelStatus.error);
        expect(service.errorMessage, 'Download timed out. Please try again.');
        expect(service.hasActiveWatchdogForTest, isFalse);
      },
    );

    test('dispose cancels a pending watchdog without leaking', () async {
      final stray = ModelDownloadService();
      stray.permissionTimeoutOverrideForTest = const Duration(milliseconds: 50);
      stray.stallTimeoutOverrideForTest = const Duration(seconds: 5);
      stray.installOverrideForTest = (token) async {
        await Completer<void>().future; // stays in flight
      };
      unawaited(stray.installModel());
      // Wait until the flight is past permission and the watchdog is armed.
      for (var i = 0; i < 100 && !stray.hasActiveWatchdogForTest; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(stray.hasActiveWatchdogForTest, isTrue);
      stray.dispose();
      expect(stray.hasActiveWatchdogForTest, isFalse);
    });
  });
}
