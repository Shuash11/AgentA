import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/services/update/github_releases_source.dart';
import 'package:aiproject/services/update/version_check_service.dart';
import 'package:aiproject/services/update/version_source.dart';

/// Fake [VersionSource] — records call counts, returns a fixed release, and
/// can simulate silent network failures (`failAll`) for the stale-cache tests.
class FakeVersionSource implements VersionSource {
  RemoteRelease? release;
  bool failAll = false;
  int calls = 0;

  FakeVersionSource({this.release});

  @override
  Future<RemoteRelease?> fetchLatestRelease() async {
    calls++;
    if (failAll) return null; // silent network-failure shape
    return release;
  }
}

/// Source whose fetch hangs until [complete] — for the in-flight guard test.
class ControlledSource implements VersionSource {
  final Completer<RemoteRelease?> _completer = Completer<RemoteRelease?>();
  int calls = 0;

  void complete(RemoteRelease? release) => _completer.complete(release);

  @override
  Future<RemoteRelease?> fetchLatestRelease() {
    calls++;
    return _completer.future;
  }
}

/// Fake [ConnectivityService] — lets tests drive the connectivity-restored
/// hook without the platform channel.
class FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<InternetStatus>.broadcast();

  void emitOnline() => _controller.add(InternetStatus.online);

  @override
  Stream<InternetStatus> get statusStream => _controller.stream;

  @override
  InternetStatus get lastStatus => InternetStatus.online;

  @override
  Future<void> init() async {}

  @override
  void dispose() => _controller.close();

  @override
  Future<bool> isOnline() async => true;

  @override
  Future<InternetStatus> checkInternetStatus() async => InternetStatus.online;
}

RemoteRelease _release(String version, {String? minVersion}) => RemoteRelease(
      version: version,
      minVersion: minVersion,
      releaseUrl: 'https://github.com/Shuash11/AgentA/releases/tag/v$version',
      notes: 'notes',
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<VersionCheckService> createdServices = [];

  VersionCheckService makeService({
    VersionSource? source,
    ConnectivityService? connectivity,
    bool enabled = true,
    Duration? minInterval,
  }) {
    final s = VersionCheckService(
      source: source,
      connectivity: connectivity,
      enabled: enabled,
      minCheckInterval: minInterval,
    );
    createdServices.add(s);
    return s;
  }

  tearDown(() {
    for (final s in createdServices) {
      s.dispose();
    }
    createdServices.clear();
  });

  group('VersionCheckService decision (Adviser rules)', () {
    test('available when latest > current', () async {
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();

      expect(source.calls, 1); // startup check fired exactly once
      expect(service.lastResult, isNotNull);
      expect(service.lastResult!.level, UpdateLevel.available);
      expect(service.lastResult!.currentVersion, '1.1.0');
      expect(service.lastResult!.currentBuild, '2');
      expect(service.lastResult!.remote!.version, '1.2.0');
    });

    test('forced when current < minVersion', () async {
      final source =
          FakeVersionSource(release: _release('1.2.0', minVersion: '1.1.5'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.forced);
    });

    test('none when current == latest', () async {
      final source = FakeVersionSource(release: _release('1.1.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.none);
    });

    test('build-number differences ignored by the decision rule', () async {
      // Current 1.1.0 build 2 vs remote 1.1.0 — build is recorded, never compared.
      final source = FakeVersionSource(release: _release('1.1.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '999');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.none);
      expect(service.lastResult!.currentBuild, '999');

      // Still just "available" (never forced) when the semver differs, whatever
      // the build numbers are.
      final newer = FakeVersionSource(release: _release('1.2.0'));
      final service2 = makeService(source: newer);
      service2.setCurrentVersionForTest(version: '1.1.0', build: '999');
      await service2.init();
      await _settle();
      expect(service2.lastResult!.level, UpdateLevel.available);
    });

    test('minVersion boundary: current == minVersion is not forced', () async {
      final source =
          FakeVersionSource(release: _release('1.2.0', minVersion: '1.1.5'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.5', build: '3');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.available);
    });
  });

  group('VersionCheckService scheduling/throttle', () {
    test('resumed re-check is throttled: min 5 min between network calls', () async {
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();
      expect(source.calls, 1);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(source.calls, 1); // throttled — no network call
    });

    test('resumed re-check fires when the throttle window has passed', () async {
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source, minInterval: Duration.zero);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();
      expect(source.calls, 1);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(source.calls, 2); // throttle window passed — re-check fired
    });

    test('connectivity-restored hook triggers a throttled check', () async {
      final connectivity = FakeConnectivity();
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(
        source: source,
        connectivity: connectivity,
        minInterval: Duration.zero,
      );
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();
      expect(source.calls, 1);

      connectivity.emitOnline();
      await _settle();
      expect(source.calls, 2); // hook wired + fired
    });

    test('checkNow bypasses the 5-min throttle (user-initiated)', () async {
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();
      expect(source.calls, 1);

      final result = await service.checkNow();
      expect(source.calls, 2);
      expect(result!.level, UpdateLevel.available);
    });

    test('checks skipped entirely when disabled (kReleaseMode gate)', () async {
      final source = FakeVersionSource(release: _release('2.0.0'));
      final service = makeService(source: source, enabled: false);
      service.setCurrentVersionForTest(version: '1.0.0', build: '1');

      await service.init();
      await _settle();

      expect(source.calls, 0);
      expect(service.lastResult, isNull);
    });

    test('init() survives PackageInfo failure (test hook injects version)', () async {
      // In the test environment PackageInfo.fromPlatform throws
      // (unmocked platform channel) — init must swallow it and still work
      // with the injected current version.
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.0.0', build: '1');

      await service.init();
      await _settle();

      expect(source.calls, 1);
      expect(service.lastResult!.level, UpdateLevel.available);
    });

    test('rate-limit backoff blocks service checks until it passes', () async {
      // Real GithubReleasesSource + MockClient returning 403 with a future
      // x-ratelimit-reset — exercises the service's backoff/throttle gate
      // end to end: fetch → no emit → no retry until the deadline passes.
      var calls = 0;
      final resetEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      final source = GithubReleasesSource(
        client: MockClient((_) async {
          calls++;
          return http.Response('{"message":"API rate limit exceeded"}', 403,
              headers: {'x-ratelimit-reset': '$resetEpoch'});
        }),
      );
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.0.0', build: '1');

      await service.init();
      await _settle();
      expect(service.lastResult, isNull); // 403 → no emit
      expect(calls, 1); // startup check only

      await service.checkNow(); // blocked by the service's backoff gate
      expect(calls, 1); // no network call while rate-limited
    });
  });

  group('VersionCheckService in-flight guard', () {
    test('no double fetch while a check is in flight', () async {
      final source = ControlledSource();
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init(); // startup check now waiting on the completer
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.calls, 1);

      final second = service.checkNow(); // in flight → returns last state
      expect(await second, isNull);
      expect(source.calls, 1);

      source.complete(_release('1.2.0'));
      await _settle();
      expect(service.lastResult!.level, UpdateLevel.available);
    });
  });

  group('VersionCheckService emissions + cache', () {
    test('resultStream broadcasts fresh outcomes only', () async {
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source);
      final events = <UpdateCheckResult>[];
      final sub = service.resultStream.listen(events.add);

      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      await service.init();
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(events, hasLength(1));
      expect(events.first.level, UpdateLevel.available);
    });

    test('null remote (404 shape) → no result emitted', () async {
      final source = FakeVersionSource(release: null);
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.0.0', build: '1');

      await service.init();
      await _settle();

      expect(source.calls, 1);
      expect(service.lastResult, isNull); // null is never "up to date"
    });

    test('cache: success is cached; a failed check never emits or clears it', () async {
      final source = FakeVersionSource(release: _release('1.2.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();
      expect(service.lastResult!.level, UpdateLevel.available);
      expect(service.cachedRelease!.version, '1.2.0');
      expect(service.lastSuccessfulCheckAt, isNotNull);

      // Simulate network failure — must never surface a dialog from stale data.
      source.failAll = true;
      final r = await service.checkNow(); // bypasses throttle
      expect(r, isNull); // no emit from a failed check
      expect(service.lastResult!.level, UpdateLevel.available); // state intact
      expect(service.cachedRelease!.version, '1.2.0'); // cache untouched
    });
  });
}
