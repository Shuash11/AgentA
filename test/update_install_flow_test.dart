import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:aiproject/cubit/update/update_cubit.dart';
import 'package:aiproject/services/update/apk_download_service.dart';
import 'package:aiproject/services/update/apk_install_service.dart';
import 'package:aiproject/services/update/install_failure_reason.dart';
import 'package:aiproject/services/update/version_check_service.dart';
import 'package:aiproject/services/update/version_source.dart';

/// Fake [VersionSource] — drives the real [VersionCheckService].
class FakeVersionSource implements VersionSource {
  ReleaseFetchResult result;
  int calls = 0;

  FakeVersionSource({RemoteRelease? release})
    : result = release == null
          ? const ReleaseNotFound()
          : ReleaseFetched(release);

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

/// Fake download service — the test owns completion and progress.
class FakeDownloadService extends ApkDownloadService {
  final List<RemoteRelease> downloads = [];
  Completer<ApkDownloadResult>? _pending;
  void Function(double progress)? _progress;
  bool cancelCalled = false;

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
    cancelCalled = true;
    complete(const ApkDownloadCancelled());
  }
}

/// Fake install service — the test owns the native event stream.
class FakeInstallService extends ApkInstallService {
  final StreamController<InstallEvent> controller =
      StreamController<InstallEvent>.broadcast();
  bool canInstallResult = true;
  int canInstallCalls = 0;
  final List<String> startedPaths = [];
  final List<int?> startedSizes = [];
  int settingsOpened = 0;

  @override
  Stream<InstallEvent> get events => controller.stream;

  @override
  Future<bool> canInstall() async {
    canInstallCalls++;
    return canInstallResult;
  }

  @override
  Future<void> startInstall({required String apkPath, int? sizeBytes}) async {
    startedPaths.add(apkPath);
    startedSizes.add(sizeBytes);
    controller.add(const InstallStarted());
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    settingsOpened++;
  }

  void emit(InstallEvent event) => controller.add(event);
}

const String _apkUrl =
    'https://github.com/Shuash11/AgentA/releases/download/v1.4.0/AgentA-v1.4.0.apk';

RemoteRelease makeRelease({String version = '1.4.0', int? sizeBytes}) =>
    RemoteRelease(
      version: version,
      downloadUrl: _apkUrl,
      assetSizeBytes: sizeBytes,
      assetSha256: 'a'.padRight(64, 'a'),
      releaseUrl: 'https://github.com/Shuash11/AgentA/releases/tag/v$version',
      notes: 'Bug fixes and improvements',
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final createdServices = <VersionCheckService>[];
  final createdCubits = <UpdateCubit>[];
  final createdFakes = <FakeInstallService>[];

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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
    for (final f in createdFakes) {
      await f.controller.close();
      f.dispose();
    }
    createdFakes.clear();
  });

  /// Cubit seeded to [UpdateStatus.available] via a real check against the
  /// fake source (running version 1.3.1 < offered 1.4.0).
  Future<UpdateCubit> makeAvailable(
    FakeVersionSource source,
    FakeDownloadService downloader, {
    FakeInstallService? installer,
  }) async {
    final service = VersionCheckService(source: source, enabled: true);
    createdServices.add(service);
    service.setCurrentVersionForTest(version: '1.3.1', build: '1');
    final installService = installer ?? FakeInstallService();
    if (installer == null) createdFakes.add(installService);
    final cubit = UpdateCubit(
      service: service,
      downloadService: downloader,
      installService: installService,
    );
    createdCubits.add(cubit);
    await cubit.checkNow();
    await settle();
    expect(cubit.state.status, UpdateStatus.available);
    return cubit;
  }

  test('download → readyToInstall with 1% progress steps', () async {
    final source = FakeVersionSource(release: makeRelease(sizeBytes: 1000));
    final downloader = FakeDownloadService();
    final cubit = await makeAvailable(source, downloader);

    unawaited(cubit.downloadUpdate());
    await settle();
    expect(cubit.state.status, UpdateStatus.downloading);
    expect(downloader.downloads, hasLength(1));

    downloader.emitProgress(0.333);
    await settle();
    expect(cubit.state.downloadProgress, 0.33);
    downloader.emitProgress(0.334); // same 1% step — no churn
    await settle();
    expect(cubit.state.downloadProgress, 0.33);
    downloader.emitProgress(0.97);
    await settle();
    expect(cubit.state.downloadProgress, 0.97);

    downloader.complete(
      ApkDownloaded(
        filePath:
            '/data/user/0/com.agenta.AgentA/files/updates/AgentA-1.4.0.apk',
        bytesReceived: 1000,
        sha256: 'a' * 64,
      ),
    );
    await settle();
    expect(cubit.state.status, UpdateStatus.readyToInstall);
    expect(cubit.state.apkPath, endsWith('AgentA-1.4.0.apk'));
    expect(cubit.state.downloadProgress, 1);
  });

  test('download failure → installFailed with the classified reason', () async {
    final source = FakeVersionSource(release: makeRelease());
    final downloader = FakeDownloadService();
    final cubit = await makeAvailable(source, downloader);

    unawaited(cubit.downloadUpdate());
    await settle();
    downloader.complete(
      const ApkDownloadFailed(InstallFailureReason.checksumMismatch),
    );
    await settle();

    expect(cubit.state.status, UpdateStatus.installFailed);
    expect(
      cubit.state.installFailureReason,
      InstallFailureReason.checksumMismatch,
    );
  });

  test('cancel mid-download → back to available', () async {
    final source = FakeVersionSource(release: makeRelease());
    final downloader = FakeDownloadService();
    final cubit = await makeAvailable(source, downloader);

    unawaited(cubit.downloadUpdate());
    await settle();
    expect(cubit.state.status, UpdateStatus.downloading);

    cubit.cancelDownload();
    await settle();

    expect(downloader.cancelCalled, isTrue);
    expect(cubit.state.status, UpdateStatus.available);
  });

  test(
    'install without the permission → permissionDenied, no session',
    () async {
      final source = FakeVersionSource(release: makeRelease());
      final downloader = FakeDownloadService();
      final installer = FakeInstallService()..canInstallResult = false;
      createdFakes.add(installer);
      final cubit = await makeAvailable(
        source,
        downloader,
        installer: installer,
      );

      unawaited(cubit.downloadUpdate());
      await settle();
      downloader.complete(
        const ApkDownloaded(
          filePath: '/x/AgentA-1.4.0.apk',
          bytesReceived: 5,
          sha256: 'a',
        ),
      );
      await settle();
      expect(cubit.state.status, UpdateStatus.readyToInstall);

      await cubit.installUpdate();
      await settle();

      expect(cubit.state.status, UpdateStatus.installFailed);
      expect(
        cubit.state.installFailureReason,
        InstallFailureReason.permissionDenied,
      );
      expect(installer.startedPaths, isEmpty);

      await cubit.openInstallPermissionSettings();
      expect(installer.settingsOpened, 1);
    },
  );

  test('install success: installing → installed (sizes forwarded)', () async {
    final source = FakeVersionSource(release: makeRelease(sizeBytes: 4242));
    final downloader = FakeDownloadService();
    final installer = FakeInstallService();
    createdFakes.add(installer);
    final cubit = await makeAvailable(source, downloader, installer: installer);

    unawaited(cubit.downloadUpdate());
    await settle();
    downloader.complete(
      const ApkDownloaded(
        filePath: '/x/AgentA-1.4.0.apk',
        bytesReceived: 4242,
        sha256: 'a',
      ),
    );
    await settle();

    await cubit.installUpdate();
    await settle();
    expect(cubit.state.status, UpdateStatus.installing);
    expect(installer.startedPaths, ['/x/AgentA-1.4.0.apk']);
    expect(installer.startedSizes, [4242]);

    installer.emit(const InstallCompleted());
    await settle();
    expect(cubit.state.status, UpdateStatus.installed);
  });

  test('install user-cancelled → installFailed(userCancelled)', () async {
    final source = FakeVersionSource(release: makeRelease());
    final downloader = FakeDownloadService();
    final installer = FakeInstallService();
    createdFakes.add(installer);
    final cubit = await makeAvailable(source, downloader, installer: installer);

    unawaited(cubit.downloadUpdate());
    await settle();
    downloader.complete(
      const ApkDownloaded(
        filePath: '/x/AgentA-1.4.0.apk',
        bytesReceived: 5,
        sha256: 'a',
      ),
    );
    await settle();
    await cubit.installUpdate();
    await settle();

    installer.emit(const InstallFailed(InstallFailureReason.userCancelled));
    await settle();

    expect(cubit.state.status, UpdateStatus.installFailed);
    expect(
      cubit.state.installFailureReason,
      InstallFailureReason.userCancelled,
    );
  });

  test(
    'retry with the verified file → install again, no re-download',
    () async {
      final source = FakeVersionSource(release: makeRelease());
      final downloader = FakeDownloadService();
      final installer = FakeInstallService();
      createdFakes.add(installer);
      final cubit = await makeAvailable(
        source,
        downloader,
        installer: installer,
      );

      unawaited(cubit.downloadUpdate());
      await settle();
      downloader.complete(
        const ApkDownloaded(
          filePath: '/x/AgentA-1.4.0.apk',
          bytesReceived: 5,
          sha256: 'a',
        ),
      );
      await settle();
      await cubit.installUpdate();
      await settle();
      installer.emit(const InstallFailed(InstallFailureReason.storage));
      await settle();
      expect(cubit.state.status, UpdateStatus.installFailed);

      await cubit.retry();
      await settle();

      expect(downloader.downloads, hasLength(1)); // no re-download
      expect(installer.startedPaths, hasLength(2)); // installed twice
      expect(cubit.state.status, UpdateStatus.installing);
    },
  );

  test('retry without a file (download failure) → re-download', () async {
    final source = FakeVersionSource(release: makeRelease());
    final downloader = FakeDownloadService();
    final cubit = await makeAvailable(source, downloader);

    unawaited(cubit.downloadUpdate());
    await settle();
    downloader.complete(const ApkDownloadFailed(InstallFailureReason.network));
    await settle();
    expect(cubit.state.status, UpdateStatus.installFailed);

    unawaited(cubit.retry());
    await settle();

    expect(downloader.downloads, hasLength(2));
    expect(cubit.state.status, UpdateStatus.downloading);
    downloader.complete(const ApkDownloadCancelled());
    await settle();
  });

  test('automatic check results never clobber an active flow', () async {
    final source = FakeVersionSource(release: makeRelease());
    final downloader = FakeDownloadService();
    final cubit = await makeAvailable(source, downloader);

    unawaited(cubit.downloadUpdate());
    await settle();
    downloader.emitProgress(0.5);
    await settle();
    expect(cubit.state.status, UpdateStatus.downloading);

    // A completed check arrives mid-download (real service, same version).
    await createdServices.last.checkNow();
    await settle();

    expect(cubit.state.status, UpdateStatus.downloading);
    expect(cubit.state.downloadProgress, 0.5);

    downloader.complete(const ApkDownloadCancelled());
    await settle();
  });

  test('dismissUntilNextVersion is a no-op during an active flow', () async {
    final source = FakeVersionSource(release: makeRelease());
    final downloader = FakeDownloadService();
    final cubit = await makeAvailable(source, downloader);

    unawaited(cubit.downloadUpdate());
    await settle();
    expect(cubit.state.status, UpdateStatus.downloading);

    await cubit.dismissUntilNextVersion();

    expect(cubit.state.status, UpdateStatus.downloading);
    downloader.complete(const ApkDownloadCancelled());
    await settle();
  });
}
