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
late FakeUrlLauncher urlLauncherForTest;

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

UpdateCubit makeCubit(VersionCheckService service) {
  final c = UpdateCubit(service: service);
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
      final source = FakeVersionSource(release: makeRelease('1.2.0'));
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
        release: makeRelease('1.2.0', minVersion: '1.1.5'),
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

    testWidgets('Update tap attempts launch on the APK asset URL', (
      tester,
    ) async {
      final source = FakeVersionSource(
        release: makeRelease('1.2.0', downloadUrl: _apkUrl),
      );
      final service = makeService(source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final cubit = makeCubit(service);

      await pumpApp(tester, cubit);
      await service.checkNow();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(urlLauncherForTest.launchedUrls, [_apkUrl]);
      // Non-forced: successful launch closes the dialog and dismisses the version.
      expect(find.text('New version available'), findsNothing);
      expect(cubit.state.status, UpdateStatus.idle);
    });

    testWidgets(
      'launch failure shows snackbar fallback and keeps the dialog open',
      (tester) async {
        urlLauncherForTest.shouldLaunch = false;
        final source = FakeVersionSource(
          release: makeRelease('1.2.0', downloadUrl: _apkUrl),
        );
        final service = makeService(source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');
        final cubit = makeCubit(service);

        await pumpApp(tester, cubit);
        await service.checkNow();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update'));
        await tester.pump(); // start snackbar entrance
        await tester.pump(const Duration(milliseconds: 300)); // finish entrance

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Update'), findsOneWidget); // dialog stays open
        expect(cubit.state.status, UpdateStatus.available); // not dismissed
      },
    );

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
