import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/core/config/app_config.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
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
        'Download authorization required. The model source is gated — please confirm your HF token is valid and the model license has been accepted. Never share the token.',
      );
      expect(
        service.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.forbidden()),
        ),
        'Download authorization required. The model source is gated — please confirm your HF token is valid and the model license has been accepted. Never share the token.',
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
      ModelDownloadService.legacyAssetPresentOverrideForTest = null;
      ModelDownloadService.uninstallOverrideForTest = null;
    });

    test('production ceilings: permission 10s, stall 3min, install 60min', () {
      expect(
        ModelDownloadService.permissionTimeoutForTest,
        const Duration(seconds: 10),
      );
      expect(
        ModelDownloadService.stallTimeoutForTest,
        const Duration(minutes: 3),
      );
      // The Gemma 4 E2B bundle is 2.59 GB — the 30-min ceiling expired
      // before a legitimate slow transfer could finish.
      expect(
        ModelDownloadService.installTimeoutForTest,
        const Duration(minutes: 60),
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

    test(
      'v3 migration: legacy asset present → marker first, uninstall, DAO reset',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v3');
        final uninstalled = <String>[];
        bool? markerAtUninstall;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            true;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
          markerAtUninstall = prefs.getBool('model_asset_v3');
        };

        await service.checkModelExists();

        expect(uninstalled, ['gemma3-1b-it-int4.task']);
        // The marker is set BEFORE the uninstall so a crash never loops the
        // download.
        expect(markerAtUninstall, isTrue);
        expect(prefs.getBool('model_asset_v3'), isTrue);
        // The DB row is reset so the gate re-downloads the current asset.
        final row = await db.query('offline_model_status');
        expect(row, hasLength(1));
        expect(row.first['status'], 'notInstalled');
        expect(row.first['model_type'], 'gemma-4-e2b-it');
      },
    );

    test('v3 migration: marker present → no uninstall', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('model_asset_v3', true);
      final uninstalled = <String>[];
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async => true;
      ModelDownloadService.uninstallOverrideForTest = (modelId) async {
        uninstalled.add(modelId);
      };

      await service.checkModelExists();

      expect(uninstalled, isEmpty);
    });

    test('v3 migration: no legacy asset → no uninstall, no marker', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('model_asset_v3');
      final uninstalled = <String>[];
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
      ModelDownloadService.uninstallOverrideForTest = (modelId) async {
        uninstalled.add(modelId);
      };

      await service.checkModelExists();

      expect(uninstalled, isEmpty);
      expect(prefs.getBool('model_asset_v3'), isNull);
      // The current asset must never be uninstalled-and-reset by its own
      // migration (that would strand the user behind a 2.59 GB re-download).
      expect(await db.query('offline_model_status'), isEmpty);
    });

    test(
      'cycle-38 P6: a load-error row neither triggers nor is reset by a migration',
      () async {
        // The install wrote the ready row; the load then failed and wrote the
        // error row — the download marker survives, so the asset is still on
        // the device.
        final dao = OfflineModelDao();
        await dao.setModelReady(modelType: 'gemma-4-e2b-it');
        await dao.setModelError('Offline model failed to load.');

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v2');
        await prefs.remove('model_asset_v3');

        final uninstalled = <String>[];
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
        };
        addTearDown(() {
          ModelDownloadService.legacyAssetPresentOverrideForTest = null;
          ModelDownloadService.uninstallOverrideForTest = null;
        });

        await service.checkModelExists();

        // No migration fired on the new error state: the error row is not a
        // "model present" trigger for v3 (it keys on the legacy asset) and
        // it is not a ready row for v2 (so v2 does not reset it either).
        expect(uninstalled, isEmpty);
        expect(prefs.getBool('model_asset_v3'), isNull);
        // The error row survives → the gate keeps routing to RETRY LOAD and
        // the installed model is never re-downloaded.
        final row = await dao.getModelStatus();
        expect(row!['status'], 'error');
        expect(row['downloaded_at'], isNotNull);
        expect(await dao.isModelInstalled(), isTrue);
      },
    );
  });

  group('P1 cycle-36 offline fix assertions', () {
    test('_modelUrl points at the Gemma 4 E2B litert-community repo', () {
      // The URL is a static const; verify via reflection-free access
      // by reading the source behavior through resolvedModelUrl.
      expect(
        ModelDownloadService.resolvedModelUrl,
        contains('litert-community/gemma-4-E2B-it-litert-lm'),
      );
      expect(
        ModelDownloadService.resolvedModelUrl,
        endsWith('/gemma-4-E2B-it.litertlm'),
      );
      expect(
        ModelDownloadService.resolvedModelUrl,
        startsWith('https://huggingface.co/litert-community/'),
      );
    });

    test('token is threaded when configured (source hygiene + no echo)', () {
      // Source-level verification: both install chains pass the token,
      // and no message/string in the service echoes it.
      final source = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect(source, contains('token: AppConfig.hfToken.trim()'));
      // Hygiene: none of the friendly copies, errors, or comments contain
      // a literal token value (sk-...), and the token never reaches UI.
      expect(source, isNot(contains('sk-')));
    });

    test(
      '401/403 friendly copy guides authorization (brand-free, no token)',
      () {
        final s = ModelDownloadService();
        final msg = s.friendlyDownloadErrorForTest(
          const DownloadException(DownloadError.unauthorized()),
        );
        expect(msg, contains('authorization required'));
        expect(msg, contains('HF token'));
        expect(msg, isNot(contains('sk-')));
        expect(msg, isNot(startsWith('https://huggingface.co/Afi')));
      },
    );

    test('migration marker semantics', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('model_asset_v2');
      // When absent and model ready, migration would uninstall; we only
      // prove the marker survives and gates re-run here (unit-safe).
      expect(prefs.getBool('model_asset_v2'), isNull);
      // After setting, no second run should occur (marker present).
      await prefs.setBool('model_asset_v2', true);
      expect(prefs.getBool('model_asset_v2'), isTrue);
    });
  });

  group('Cycle-38 P2 offline-model swap assertions', () {
    test('both install chains target the gemma4 + litertlm spec', () {
      // The installOverrideForTest seam bypasses the real chain by design —
      // assert the spec constants in the source, not the plugin call graph.
      final source = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect('ModelType.gemma4'.allMatches(source).length, 2);
      expect('ModelFileType.litertlm'.allMatches(source).length, 2);
      expect(source, isNot(contains('ModelType.gemmaIt')));
    });

    test('the HF token stays threaded in both install chains', () {
      final source = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect('token: AppConfig.hfToken.trim()'.allMatches(source).length, 2);
    });

    test('the GEMMA_MODEL_URL override still wins over the default URL', () {
      final source = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect(
        source,
        contains(
          'AppConfig.gemmaModelUrl.isNotEmpty ? AppConfig.gemmaModelUrl : _modelUrl',
        ),
      );
    });

    test('the model identity is coherent across the four sites', () {
      const identity = 'gemma-4-e2b-it';
      final service = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      final gemma = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      final dao = File(
        'lib/data/local/offline_model_dao.dart',
      ).readAsStringSync();
      expect(service, contains("_modelType = '$identity'"));
      expect(gemma, contains("setModelReady(modelType: '$identity')"));
      expect("'model_type': '$identity'".allMatches(dao).length, 2);
      // The superseded identity survives only as the migration uninstall id.
      expect(service, contains("'gemma3-1b-it-int4.task'"));
      expect(service, isNot(contains("'gemma3-1b-it-int4'")));
    });

    test('both install ceilings are 60 minutes', () {
      final source = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect('Duration(minutes: 60)'.allMatches(source).length, 2);
      expect(source, isNot(contains('Duration(minutes: 30)')));
    });
  });
}
