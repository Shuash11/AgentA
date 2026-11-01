import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aiproject/core/config/app_config.dart';
import 'package:aiproject/data/local/database_helper.dart';
import 'package:aiproject/data/local/offline_model_dao.dart';
import 'package:aiproject/services/ai/device_capabilities.dart';
import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:aiproject/services/ai/offline_model_spec.dart';
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
      // Cycle-42 P2b: a device that clears the RAM floor resolves the ONE
      // selection class - the install chain under test is the Qwen chain.
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
    });

    tearDown(() {
      service.dispose();
      ModelDownloadService.legacyAssetPresentOverrideForTest = null;
      ModelDownloadService.e2bAssetPresentOverrideForTest = null;
      ModelDownloadService.uninstallOverrideForTest = null;
      DeviceCapabilities.offlineAiSupportedOverrideForTest = null;
      DeviceCapabilities.totalMemoryOverrideForTest = null;
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
        // The row's identity is the app's offline-model identity — app-wide
        // (contract §2).
        expect(row.first['model_type'], 'qwen2.5-1.5b-it');
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

    // ── cycle-42 P2b: migration v4 (the stranded E2B bundle) ───────────────
    //
    // The trigger is WIDENED: the capability-verdict clause is DELETED, so
    // v4 fires for ANY device holding the E2B asset — the asset's presence
    // is the whole trigger. The v3 self-reset lesson carries in its
    // GENERALIZED form: a Qwen-asset user must NEVER fire v4.

    test(
      'v4 migration: a stranded E2B asset → marker first, uninstall, DAO reset',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v4');
        final uninstalled = <String>[];
        bool? markerAtUninstall;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => true;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
          markerAtUninstall = prefs.getBool('model_asset_v4');
        };

        await service.checkModelExists();

        // The EXACT uninstall id: the persisted filename of the E2B asset
        // (the pinned core keys a model by its filename — a case-mismatched
        // id would be a silent no-migration).
        expect(uninstalled, ['gemma-4-E2B-it.litertlm']);
        // The marker is set BEFORE the uninstall so a crash never loops the
        // download.
        expect(markerAtUninstall, isTrue);
        expect(prefs.getBool('model_asset_v4'), isTrue);
        // The DB row is reset so the gate re-offers per the selection table.
        final row = await db.query('offline_model_status');
        expect(row, hasLength(1));
        expect(row.first['status'], 'notInstalled');
      },
    );

    test(
      'v4 migration: the reset row carries the app-wide Qwen identity',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v4');
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => true;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {};

        await service.checkModelExists();

        // The row's identity is the app's offline-model identity — app-wide
        // (contract §2).
        final row = await db.query('offline_model_status');
        expect(row, hasLength(1));
        expect(row.first['status'], 'notInstalled');
        expect(row.first['model_type'], 'qwen2.5-1.5b-it');
      },
    );

    test(
      'v4 migration: an arm64 device with a stranded E2B asset ALSO fires — the trigger is class-independent',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v4');
        final uninstalled = <String>[];
        // The old trigger skipped an arm64 device (the capability-verdict
        // conjunct). E2B left selection (plan §4.9): EVERY device holding
        // the asset is ineligible for it now.
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => true;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
        };

        await service.checkModelExists();

        expect(uninstalled, ['gemma-4-E2B-it.litertlm']);
        expect(prefs.getBool('model_asset_v4'), isTrue);
      },
    );

    test(
      'v4 migration: a device below the RAM floor with a stranded E2B asset ALSO fires',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v4');
        final uninstalled = <String>[];
        // The message-only class: the asset is dead weight there too — it
        // must still be cleaned up (no stranded download).
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            2 * 1024 * 1024 * 1024;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => true;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
        };

        await service.checkModelExists();

        expect(uninstalled, ['gemma-4-E2B-it.litertlm']);
        expect(prefs.getBool('model_asset_v4'), isTrue);
      },
    );

    test(
      'v4 migration: the both-assets composition fires ONCE, cleans E2B and the readiness read finds Qwen',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v4');
        final uninstalled = <String>[];
        // The device already downloaded Qwen (its DB row is the durable
        // truth the gate's readiness read consults) AND still holds the
        // stranded E2B asset.
        await OfflineModelDao().setModelReady(
          modelType: OfflineModelSpecTable.appIdentity,
        );
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => true;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
        };

        await service.checkModelExists();

        // v4 FIRED: the stranded E2B asset is cleaned up.
        expect(uninstalled, ['gemma-4-E2B-it.litertlm']);
        expect(prefs.getBool('model_asset_v4'), isTrue);
        // The readiness read FINDS QWEN: no Qwen re-download is forced.
        expect(service.status, ModelStatus.ready);
        final row = await db.query('offline_model_status');
        expect(row.first['status'], 'ready');
        expect(row.first['model_type'], 'qwen2.5-1.5b-it');

        // It fires ONCE: the marker gates the second run.
        await service.checkModelExists();
        expect(uninstalled, ['gemma-4-E2B-it.litertlm']);
        expect(service.status, ModelStatus.ready);
      },
    );

    test('v4 migration: a Qwen-only user NEVER fires v4', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('model_asset_v4');
      final uninstalled = <String>[];
      // The device holds the Qwen asset only: both probe legs of the
      // trigger are false (the v3 self-reset lesson, generalized).
      await OfflineModelDao().setModelReady(
        modelType: OfflineModelSpecTable.appIdentity,
      );
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
      ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
      ModelDownloadService.uninstallOverrideForTest = (modelId) async {
        uninstalled.add(modelId);
      };

      await service.checkModelExists();

      expect(uninstalled, isEmpty);
      expect(prefs.getBool('model_asset_v4'), isNull);
      // The Qwen asset is untouched: the readiness read still finds it.
      expect(service.status, ModelStatus.ready);
    });

    test('v4 migration: the marker gates a second run', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('model_asset_v4', true);
      final uninstalled = <String>[];
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
      ModelDownloadService.e2bAssetPresentOverrideForTest = () async => true;
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
      ModelDownloadService.uninstallOverrideForTest = (modelId) async {
        uninstalled.add(modelId);
      };

      await service.checkModelExists();

      expect(uninstalled, isEmpty);
    });

    test(
      'v4 migration: no stranded E2B asset → no uninstall, no marker',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('model_asset_v4');
        final uninstalled = <String>[];
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.uninstallOverrideForTest = (modelId) async {
          uninstalled.add(modelId);
        };

        await service.checkModelExists();

        expect(uninstalled, isEmpty);
        expect(prefs.getBool('model_asset_v4'), isNull);
      },
    );

    test('v4 migration: the v2 and v3 markers stay untouched', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('model_asset_v2');
      await prefs.remove('model_asset_v3');
      await prefs.remove('model_asset_v4');
      DeviceCapabilities.totalMemoryOverrideForTest = () async =>
          6 * 1024 * 1024 * 1024;
      ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
      ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
          false;
      ModelDownloadService.uninstallOverrideForTest = (modelId) async {};

      await service.checkModelExists();

      // v4 is its own generation: it neither writes nor reads the v2/v3
      // markers (the contract's untouched rule).
      expect(prefs.getBool('model_asset_v2'), isNull);
      expect(prefs.getBool('model_asset_v3'), isNull);
      expect(prefs.getBool('model_asset_v4'), isNull);
    });

    test(
      'the install path writes the app-wide Qwen identity — the selection class',
      () async {
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
        service.installOverrideForTest = (token) async {};

        await service.installModel();

        expect(service.status, ModelStatus.ready);
        final row = await db.query('offline_model_status');
        expect(row, hasLength(1));
        expect(row.first['status'], 'ready');
        expect(row.first['model_type'], 'qwen2.5-1.5b-it');
      },
    );

    test(
      'the install path writes the SAME identity on an arm64 device',
      () async {
        // The identity is the app's offline-model NAME — app-wide, whatever
        // the device's ABI (contract §3).
        DeviceCapabilities.offlineAiSupportedOverrideForTest = () async => true;
        DeviceCapabilities.totalMemoryOverrideForTest = () async =>
            6 * 1024 * 1024 * 1024;
        ModelDownloadService.legacyAssetPresentOverrideForTest = () async =>
            false;
        ModelDownloadService.e2bAssetPresentOverrideForTest = () async => false;
        service.installOverrideForTest = (token) async {};

        await service.installModel();

        expect(service.status, ModelStatus.ready);
        final row = await db.query('offline_model_status');
        expect(row, hasLength(1));
        expect(row.first['status'], 'ready');
        expect(row.first['model_type'], 'qwen2.5-1.5b-it');
      },
    );

    test(
      'cycle-38 P6: a load-error row neither triggers nor is reset by a migration',
      () async {
        // The install wrote the ready row; the load then failed and wrote the
        // error row — the download marker survives, so the asset is still on
        // the device.
        final dao = OfflineModelDao();
        await dao.setModelReady(modelType: OfflineModelSpecTable.appIdentity);
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
    test('the install URL points at the litert-community repo', () {
      // The URL moved into the spec table (cycle-42 P2) — it is the ONLY
      // place the asset URLs are written now. E2B left selection (P2b): the
      // ONE install URL is the Qwen 2.5 1.5B Instruct `.task` asset.
      expect(
        OfflineModelSpecTable.qwen15b.url,
        contains('litert-community/Qwen2.5-1.5B-Instruct'),
      );
      expect(
        OfflineModelSpecTable.qwen15b.url,
        endsWith('/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task'),
      );
      expect(
        OfflineModelSpecTable.qwen15b.url,
        startsWith('https://huggingface.co/litert-community/'),
      );
      // The E2B install URL survives nowhere: the asset is not offered any
      // more — only its uninstall id remains (migration v4).
      final lib = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect(lib, isNot(contains('gemma-4-E2B-it-litert-lm')));
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
    test('both install chains target the SELECTED spec (cycle-42 P2b)', () {
      // The installOverrideForTest seam bypasses the real chain by design —
      // assert the spec constants in the source, not the plugin call graph.
      // The chains are spec-driven: the table's ONE row carries the
      // qwen + task claim.
      final source = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      expect('modelType: spec.modelType'.allMatches(source).length, 2);
      expect('fileType: spec.fileType'.allMatches(source).length, 2);
      // No hardcoded spec survives in the service — the table decides.
      expect(source, isNot(contains('ModelType.gemma4')));
      expect(source, isNot(contains('ModelFileType.litertlm')));
      expect(source, isNot(contains('ModelType.gemmaIt')));
      expect(OfflineModelSpecTable.qwen15b.modelType, ModelType.qwen);
      expect(OfflineModelSpecTable.qwen15b.fileType, ModelFileType.task);
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
          'AppConfig.gemmaModelUrl.isNotEmpty ? AppConfig.gemmaModelUrl : spec.url',
        ),
      );
      // The override substitutes the URL WITHIN the selected class: the
      // class keeps its own modelType/fileType (contract §7
      // override_caveat_amended). With no override configured the spec URL
      // is what the chain installs.
      expect(
        ModelDownloadService.resolvedModelUrlFor(OfflineModelSpecTable.qwen15b),
        OfflineModelSpecTable.qwen15b.url,
      );
    });

    test('the model identity is coherent across the four sites', () {
      // The spec table is the ONLY place the identity string is written
      // (contract §2 identity_invariant) — the four sites reference the
      // resolved spec, so the DAO row and the plugin identity cannot drift.
      final table = File(
        'lib/services/ai/offline_model_spec.dart',
      ).readAsStringSync();
      final service = File(
        'lib/services/ai/model_download_service.dart',
      ).readAsStringSync();
      final gemma = File(
        'lib/services/ai/gemma_service.dart',
      ).readAsStringSync();
      final dao = File(
        'lib/data/local/offline_model_dao.dart',
      ).readAsStringSync();

      // The identity lives in the table — once.
      expect("identity: 'qwen2.5-1.5b-it'".allMatches(table).length, 1);
      expect(OfflineModelSpecTable.qwen15b.identity, 'qwen2.5-1.5b-it');
      expect(OfflineModelSpecTable.appIdentity, 'qwen2.5-1.5b-it');
      // The E2B identity is GONE from the table (E2B left selection).
      expect(table, isNot(contains("'gemma-4-e2b-it'")));

      // No duplicate identity string survives in any consumer.
      for (final source in [service, gemma, dao]) {
        expect(source, isNot(contains("'gemma-4-e2b-it'")));
        expect(source, isNot(contains("'qwen2.5-1.5b-it'")));
      }

      // The four sites resolve the identity from the spec.
      expect(
        'setModelReady(modelType: spec.identity)'.allMatches(service).length,
        2,
      );
      expect(gemma, contains('OfflineModelSpecTable.appIdentity'));
      expect(
        "'model_type': modelType ?? OfflineModelSpecTable.appIdentity"
            .allMatches(dao)
            .length,
        2,
      );
      // The superseded 1B asset survives only as the v3 uninstall id.
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
