import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/cubit/update/update_cubit.dart';
import 'package:aiproject/presentation/shared/update_available_dialog.dart';
import 'package:aiproject/presentation/shared/update_dialog_host.dart';
import 'package:aiproject/services/update/apk_download_service.dart';
import 'package:aiproject/services/update/apk_install_service.dart';
import 'package:aiproject/services/update/install_failure_reason.dart';
import 'package:aiproject/services/update/version_check_service.dart';
import 'package:aiproject/services/update/version_source.dart';

/// Fake [VersionSource] — drives the real [VersionCheckService] in tests.
class FakeVersionSource implements VersionSource {
  ReleaseFetchResult result;
  int calls = 0;

  FakeVersionSource({RemoteRelease? release})
    : result = release == null
          ? const ReleaseNotFound()
          : ReleaseFetched(release);

  /// Switches the result mid-test (e.g. a newer release arrives).
  set release(RemoteRelease? value) {
    result = value == null ? const ReleaseNotFound() : ReleaseFetched(value);
  }

  @override
  Future<ReleaseFetchResult> fetchLatestRelease() async {
    calls++;
    return result;
  }

  @override
  DateTime? get backoffUntil => null;
}

/// Fake [UrlLauncherPlatform] — records launches for the Update-tap tests.
class FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];
  bool shouldLaunch = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    return shouldLaunch;
  }
}

const String _apkUrl =
    'https://github.com/Shuash11/AgentA/releases/download/v1.2.0/AgentA-v1.2.0.apk';

final List<VersionCheckService> createdServices = [];
final List<UpdateCubit> createdCubits = [];
final List<ApkInstallService> createdInstallers = [];
late FakeUrlLauncher urlLauncherForTest;

/// Fake download service — the test owns completion and progress
/// (cycle-28 P5 dialog tests; mirrors the P4 harness in
/// update_install_flow_test.dart).
class FakeDownloadService extends ApkDownloadService {
  final List<RemoteRelease> downloads = [];
  Completer<ApkDownloadResult>? _pending;
  void Function(double progress)? _progress;

  @override
  Future<ApkDownloadResult> download(
    RemoteRelease release, {
    required void Function(double progress) onProgress,
  }) {
    downloads.add(release);
    _progress = onProgress;
    _pending = Completer<ApkDownloadResult>();
    return _pending!.future;
  }

  void emitProgress(double progress) => _progress?.call(progress);

  void complete(ApkDownloadResult result) {
    if (_pending != null && !_pending!.isCompleted) _pending!.complete(result);
  }

  @override
  void cancel() {
    complete(const ApkDownloadCancelled());
  }
}

/// Fake install service — the test owns the native event stream.
class FakeInstallService extends ApkInstallService {
  final StreamController<InstallEvent> controller =
      StreamController<InstallEvent>.broadcast();
  bool canInstallResult = true;
  final List<String> startedPaths = [];
  int settingsOpened = 0;

  @override
  Stream<InstallEvent> get events => controller.stream;

  @override
  Future<bool> canInstall() async => canInstallResult;

  @override
  Future<void> startInstall({required String apkPath, int? sizeBytes}) async {
    startedPaths.add(apkPath);
    controller.add(const InstallStarted());
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    settingsOpened++;
  }

  void emit(InstallEvent event) => controller.add(event);
}

RemoteRelease makeRelease(
  String version, {
  String? minVersion,
  String? downloadUrl,
}) => RemoteRelease(
  version: version,
  minVersion: minVersion,
  downloadUrl: downloadUrl,
  releaseUrl: 'https://github.com/Shuash11/AgentA/releases/tag/v$version',
  notes: 'Bug fixes and improvements',
);

/// Lets the cubit's async dismissal load settle (in-memory prefs respond in
/// microtasks; the service's fake fetch too).
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

VersionCheckService makeService(FakeVersionSource source) {
  final s = VersionCheckService(source: source, enabled: true);
  createdServices.add(s);
  return s;
}

UpdateCubit makeCubit(
  VersionCheckService service, {
  ApkDownloadService? downloader,
  ApkInstallService? installer,
}) {
  final installService = installer;
  if (installService != null) createdInstallers.add(installService);
  final c = UpdateCubit(
    service: service,
    downloadService: downloader,
    installService: installService,
  );
  createdCubits.add(c);
  return c;
}

/// Pumps a minimal app replicating the production wiring: the update dialog
/// host wraps the whole app via `MaterialApp builder:` (overlay over any
/// screen), with the ThemeCubit + UpdateCubit provided above it.
Future<void> pumpApp(WidgetTester tester, UpdateCubit cubit) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<UpdateCubit>.value(value: cubit),
      ],
      child: MaterialApp(
        navigatorKey: UpdateDialogHost.navigatorKey,
        builder: (context, child) =>
            UpdateDialogHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('AgentA'))),
      ),
    ),
  );
  await tester.pump(); // let the host's post-frame seed evaluate
}

void main() {
  // The cubit constructs the install-channel service (cycle-28 P4), which
  // binds a platform-channel handler — ensure the binding for plain tests too.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh in-memory prefs store + URL launcher fake per test.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    urlLauncherForTest = FakeUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncherForTest;
  });

  tearDown(() async {
    for (final c in createdCubits) {
      await c.close();
    }
    createdCubits.clear();
    for (final s in createdServices) {
      s.dispose();
    }
    createdServices.clear();
    for (final i in createdInstallers) {
      i.dispose();
    }
    createdInstallers.clear();
  });

  group('UpdateCubit state mapping (service levels → status)', () {
    test(
      'available maps to UpdateStatus.available with version info',
      () async {
        final source = FakeVersionSource(release: makeRelease('1.2.0'));
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final cubit = makeCubit(service);
        await settle();

        await service.checkNow(); // fresh network result → cubit maps
        await settle();

        expect(cubit.state.status, UpdateStatus.available);
        expect(cubit.state.currentVersion, '1.1.0');
        expect(cubit.state.currentBuild, 2);
        expect(cubit.state.remote!.version, '1.2.0');
      },
    );

    test('none maps to UpdateStatus.idle', () async {
      final source = FakeVersionSource(release: makeRelease('1.1.0'));
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);
      await settle();

      await service.checkNow();
      await settle();

      expect(cubit.state.status, UpdateStatus.idle);
    });

    test('forced maps to UpdateStatus.forced and cannot be dismissed', () async {
      final source = FakeVersionSource(
        release: makeRelease('1.2.0', minVersion: '1.1.5'),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);
      await settle();

      await service.checkNow();
      await settle();

      expect(cubit.state.status, UpdateStatus.forced);
      expect(cubit.state.isForced, isTrue);

      // Forced: dismissUntilNextVersion refuses — status unchanged, nothing persisted.
      await cubit.dismissUntilNextVersion();
      await settle();
      expect(cubit.state.status, UpdateStatus.forced);
      expect(cubit.dismissedVersion, isNull);
      final persisted = await SharedPreferencesAsync().getString(
        UpdateCubit.dismissedVersionKey,
      );
      expect(persisted, isNull);
    });

    test('checkNow delegates to the service (checking → available)', () async {
      final source = FakeVersionSource(release: makeRelease('1.2.0'));
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);
      await settle();

      await cubit.checkNow();
      await settle();

      expect(cubit.state.status, UpdateStatus.available);
    });
  });

  group('UpdateCubit dismissal (SharedPreferencesAsync, show rules)', () {
    test(
      'dismissed version suppressed for the same version; newer re-triggers',
      () async {
        // Remote NEWER than current → dialog shows as available.
        final source = FakeVersionSource(release: makeRelease('1.1.5'));
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final cubit = makeCubit(service);
        await settle();

        await service.checkNow();
        await settle();
        expect(cubit.state.status, UpdateStatus.available);

        await cubit.dismissUntilNextVersion();
        await settle();
        expect(cubit.state.status, UpdateStatus.idle);
        expect(cubit.dismissedVersion, '1.1.5');

        // Same version again → stays suppressed.
        await service.checkNow();
        await settle();
        expect(cubit.state.status, UpdateStatus.idle);

        // A newer release automatically re-triggers.
        source.release = makeRelease('1.2.0');
        await service.checkNow();
        await settle();
        expect(cubit.state.status, UpdateStatus.available);
      },
    );

    test('dismissal persists and a fresh cubit loads it (roundtrip)', () async {
      final source = FakeVersionSource(release: makeRelease('1.1.0'));
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);
      await settle();

      await service.checkNow();
      await settle();
      await cubit.dismissUntilNextVersion();
      await settle();

      final persisted = await SharedPreferencesAsync().getString(
        UpdateCubit.dismissedVersionKey,
      );
      expect(persisted, '1.1.0');

      // Fresh cubit (same store) loads the persisted dismissal and suppresses.
      final cubit2 = makeCubit(service);
      await settle();
      expect(cubit2.dismissedVersion, '1.1.0');
      await service.checkNow();
      await settle();
      expect(cubit2.state.status, UpdateStatus.idle);
    });
  });

  group('UpdateDialogHost + UpdateAvailableDialog (widget)', () {
    testWidgets('dialog shows on available when not dismissed', (tester) async {
      final source = FakeVersionSource(
        release: makeRelease('1.2.0', downloadUrl: _apkUrl),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      expect(find.text('New version available'), findsOneWidget);
      expect(find.text('1.1.0 → 1.2.0'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('AgentA'), findsOneWidget); // app still beneath
    });

    testWidgets(
      'not shown after dismissUntilNextVersion for the same version',
      (tester) async {
        // Remote NEWER than current → dialog shows as available.
        final source = FakeVersionSource(release: makeRelease('1.2.0'));
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final cubit = makeCubit(service);

        await pumpApp(tester, cubit);
        await service.checkNow();
        await tester.pumpAndSettle();
        expect(find.text('New version available'), findsOneWidget);

        await tester.tap(find.text('Later'));
        await tester.pumpAndSettle(); // dialog closes + dismissal persisted
        expect(find.text('New version available'), findsNothing);

        // Same version again → no dialog.
        await service.checkNow();
        await tester.pumpAndSettle();
        expect(find.text('New version available'), findsNothing);
      },
    );

    testWidgets('shown again for a newer version after dismissal', (
      tester,
    ) async {
      // Remote NEWER than current → dialog shows, then is dismissed.
      final source = FakeVersionSource(release: makeRelease('1.2.0'));
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsNothing);

      // Newer release → dialog re-triggers automatically.
      source.release = makeRelease('1.3.0');
      await service.checkNow();
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsOneWidget);
      expect(find.text('1.1.0 → 1.3.0'), findsOneWidget);
    });

    testWidgets('forced shows non-dismissible Update-only', (tester) async {
      final source = FakeVersionSource(
        release: makeRelease(
          '1.2.0',
          minVersion: '1.1.5',
          downloadUrl: _apkUrl,
        ),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Later'), findsNothing); // forced: no dismiss button
    });

    testWidgets('Update tap starts the in-app download (no browser launch)', (
      tester,
    ) async {
      final source = FakeVersionSource(
        release: makeRelease('1.2.0', downloadUrl: _apkUrl),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final downloader = FakeDownloadService();
      final cubit = makeCubit(service, downloader: downloader);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pump();

      // The dialog morphs to the in-app progress state; the browser is NOT
      // opened (P5: the browser survives only as the manual fallback).
      expect(find.text('Downloading update… 0%'), findsOneWidget);
      expect(urlLauncherForTest.launchedUrls, isEmpty);
      expect(cubit.state.status, UpdateStatus.downloading);

      // Progress renders live in the dialog.
      downloader.emitProgress(0.42);
      await tester.pump();
      expect(find.text('Downloading update… 42%'), findsOneWidget);

      // Cancel returns the dialog to the availability state.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsOneWidget);
      expect(cubit.state.status, UpdateStatus.available);
    });

    testWidgets(
      'full flow: downloading → readyToInstall → installing → installed',
      (tester) async {
        final source = FakeVersionSource(
          release: makeRelease('1.2.0', downloadUrl: _apkUrl),
        );
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final downloader = FakeDownloadService();
        final installer = FakeInstallService();
        final cubit = makeCubit(
          service,
          downloader: downloader,
          installer: installer,
        );

        await pumpApp(tester, cubit);
        await service.checkNow();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update'));
        await tester.pump();
        expect(find.text('Downloading update… 0%'), findsOneWidget);

        downloader.complete(
          ApkDownloaded(
            filePath: '/x/AgentA-1.2.0.apk',
            bytesReceived: 10,
            sha256: 'a',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ready to install'), findsOneWidget);
        expect(find.text('Install now'), findsOneWidget);

        await tester.tap(find.text('Install now'));
        // Indeterminate spinner: pump without settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Installing…'), findsOneWidget);
        expect(installer.startedPaths, ['/x/AgentA-1.2.0.apk']);

        installer.emit(const InstallCompleted());
        await tester.pump();
        expect(find.text('Update installed'), findsOneWidget);
        expect(find.text('Restart the app to finish.'), findsOneWidget);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateAvailableDialog), findsNothing);
      },
    );

    testWidgets('install failure (userCancelled) shows copy + retry', (
      tester,
    ) async {
      final source = FakeVersionSource(
        release: makeRelease('1.2.0', downloadUrl: _apkUrl),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final downloader = FakeDownloadService();
      final installer = FakeInstallService();
      final cubit = makeCubit(
        service,
        downloader: downloader,
        installer: installer,
      );

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pump();
      downloader.complete(
        ApkDownloaded(
          filePath: '/x/AgentA-1.2.0.apk',
          bytesReceived: 10,
          sha256: 'a',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install now'));
      await tester.pump();
      installer.emit(const InstallFailed(InstallFailureReason.userCancelled));
      await tester.pump();

      expect(find.text('Installation cancelled'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // Retry with the verified file on hand → installing again.
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Installing…'), findsOneWidget);
      expect(installer.startedPaths, hasLength(2));
    });

    testWidgets(
      'signatureMismatch → proper-English copy + manual browser fallback',
      (tester) async {
        final source = FakeVersionSource(
          release: makeRelease('1.2.0', downloadUrl: _apkUrl),
        );
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final downloader = FakeDownloadService();
        final installer = FakeInstallService();
        final cubit = makeCubit(
          service,
          downloader: downloader,
          installer: installer,
        );

        await pumpApp(tester, cubit);
        await service.checkNow();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update'));
        await tester.pump();
        downloader.complete(
          ApkDownloaded(
            filePath: '/x/AgentA-1.2.0.apk',
            bytesReceived: 10,
            sha256: 'a',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Install now'));
        await tester.pump();
        installer.emit(
          const InstallFailed(InstallFailureReason.signatureMismatch),
        );
        await tester.pump();

        expect(
          find.text(
            'Update cannot be installed (signature mismatch). Please download manually.',
          ),
          findsOneWidget,
        );
        expect(find.text('Download manually'), findsOneWidget);

        // The sanctioned browser exception: the manual fallback opens the
        // release page and closes the dialog.
        await tester.tap(find.text('Download manually'));
        await tester.pumpAndSettle();
        expect(urlLauncherForTest.launchedUrls, isNotEmpty);
        expect(find.byType(UpdateAvailableDialog), findsNothing);
      },
    );

    testWidgets(
      'permissionDenied → routes to the install-permission settings',
      (tester) async {
        final source = FakeVersionSource(
          release: makeRelease('1.2.0', downloadUrl: _apkUrl),
        );
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final downloader = FakeDownloadService();
        final installer = FakeInstallService()..canInstallResult = false;
        final cubit = makeCubit(
          service,
          downloader: downloader,
          installer: installer,
        );

        await pumpApp(tester, cubit);
        await service.checkNow();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update'));
        await tester.pump();
        downloader.complete(
          ApkDownloaded(
            filePath: '/x/AgentA-1.2.0.apk',
            bytesReceived: 10,
            sha256: 'a',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Install now'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Permission needed'), findsOneWidget);
        expect(find.text('Open settings'), findsOneWidget);
        expect(installer.startedPaths, isEmpty); // no install attempted

        await tester.tap(find.text('Open settings'));
        await tester.pump();
        expect(installer.settingsOpened, 1);
      },
    );

    testWidgets('no download URL → Update falls back to the browser', (
      tester,
    ) async {
      // No downloadUrl on the release: the in-app flow cannot start — Update
      // becomes the sanctioned manual fallback (browser to the release page).
      final source = FakeVersionSource(release: makeRelease('1.2.0'));
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final downloader = FakeDownloadService();
      final cubit = makeCubit(service, downloader: downloader);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      expect(find.text('Download manually'), findsOneWidget);
      await tester.tap(find.text('Download manually'));
      await tester.pumpAndSettle();

      expect(urlLauncherForTest.launchedUrls, [
        'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0',
      ]);
      expect(find.text('New version available'), findsNothing);
      expect(cubit.state.status, UpdateStatus.idle);
    });

    testWidgets('non-https manual-fallback URL never opens the browser', (
      tester,
    ) async {
      // H3 (P7): the manual fallback is https-only — a non-https target shows
      // the failure snackbar and never reaches the URL launcher.
      final source = FakeVersionSource(
        release: RemoteRelease(
          version: '1.2.0',
          releaseUrl: 'http://insecure.example.com/AgentA',
        ),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final downloader = FakeDownloadService();
      final cubit = makeCubit(service, downloader: downloader);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      expect(find.text('Download manually'), findsOneWidget);
      await tester.tap(find.text('Download manually'));
      await tester.pump(); // snackbar entrance
      await tester.pump(const Duration(milliseconds: 300));

      expect(urlLauncherForTest.launchedUrls, isEmpty);
      expect(find.text('Could not open the download page.'), findsOneWidget);
      expect(cubit.state.status, UpdateStatus.available); // dialog stays open
    });

    testWidgets('no duplicate dialog while showing; content updates live', (
      tester,
    ) async {
      final source = FakeVersionSource(release: makeRelease('1.2.0'));
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);

      // A newer release arrives while the dialog is open.
      source.release = makeRelease('1.3.0');
      await service.checkNow();
      await tester.pumpAndSettle();

      expect(find.byType(UpdateAvailableDialog), findsOneWidget); // still one
      expect(find.text('1.1.0 → 1.3.0'), findsOneWidget); // live content update
    });
  });
}
