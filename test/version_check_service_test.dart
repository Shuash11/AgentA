import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/services/update/github_releases_source.dart';
import 'package:aiproject/services/update/version_check_service.dart';
import 'package:aiproject/services/update/version_source.dart';

/// Fake [VersionSource] — returns a fixed classified result, records calls,
/// and allows switching the result mid-test (e.g. success → failure).
class FakeVersionSource implements VersionSource {
  ReleaseFetchResult result;
  int calls = 0;

  FakeVersionSource(this.result);

  @override
  Future<ReleaseFetchResult> fetchLatestRelease() async {
    calls++;
    return result;
  }

  @override
  DateTime? get backoffUntil => null;
}

/// Source whose fetch hangs until [complete] — for the in-flight join tests.
class ControlledSource implements VersionSource {
  final Completer<ReleaseFetchResult> _completer =
      Completer<ReleaseFetchResult>();
  int calls = 0;

  void complete(ReleaseFetchResult result) => _completer.complete(result);

  @override
  Future<ReleaseFetchResult> fetchLatestRelease() {
    calls++;
    return _completer.future;
  }

  @override
  DateTime? get backoffUntil => null;
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

ReleaseFetchResult _fetched(String version, {String? minVersion}) =>
    ReleaseFetched(_release(version, minVersion: minVersion));

/// A minimal valid 200 payload for the real GithubReleasesSource tests.
String _ok200Body() => jsonEncode({
  'tag_name': 'v1.2.0',
  'draft': false,
  'prerelease': false,
  'html_url': 'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0',
  'body': '',
  'assets': const [],
});

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

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
      final source = FakeVersionSource(_fetched('1.2.0'));
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

    test(
      'P1 regression: current 1.2.4 vs the real v1.2.5 payload → available',
      () async {
        // Shape verified in the P1 diagnosis (authenticated read of the real
        // release): v1.2.5, not draft/prerelease, no min-version marker, APK
        // asset. This is the exact installer scenario the defect report used.
        final source = FakeVersionSource(
          ReleaseFetched(
            RemoteRelease(
              version: '1.2.5',
              releaseUrl:
                  'https://github.com/Shuash11/AgentA/releases/tag/v1.2.5',
              downloadUrl:
                  'https://github.com/Shuash11/AgentA/releases/download/v1.2.5/AgentA-v1.2.5.apk',
              notes: 'Bug fixes and improvements',
            ),
          ),
        );
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.2.4', build: '1');

        final outcome = await service.checkNow();

        expect(outcome, isA<UpdateCheckCompleted>());
        final result = (outcome as UpdateCheckCompleted).result;
        expect(result.level, UpdateLevel.available);
        expect(result.remote!.version, '1.2.5');
        expect(service.cachedRelease!.version, '1.2.5');
      },
    );

    test('forced when current < minVersion', () async {
      final source = FakeVersionSource(_fetched('1.2.0', minVersion: '1.1.5'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.forced);
    });

    test('none when current == latest', () async {
      final source = FakeVersionSource(_fetched('1.1.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.none);
    });

    test('build-number differences ignored by the decision rule', () async {
      // Current 1.1.0 build 2 vs remote 1.1.0 — build is recorded, never compared.
      final source = FakeVersionSource(_fetched('1.1.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '999');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.none);
      expect(service.lastResult!.currentBuild, '999');

      // Still just "available" (never forced) when the semver differs, whatever
      // the build numbers are.
      final newer = FakeVersionSource(_fetched('1.2.0'));
      final service2 = makeService(source: newer);
      service2.setCurrentVersionForTest(version: '1.1.0', build: '999');
      await service2.init();
      await _settle();
      expect(service2.lastResult!.level, UpdateLevel.available);
    });

    test('minVersion boundary: current == minVersion is not forced', () async {
      final source = FakeVersionSource(_fetched('1.2.0', minVersion: '1.1.5'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.5', build: '3');

      await service.init();
      await _settle();

      expect(service.lastResult!.level, UpdateLevel.available);
    });
  });

  group('classified fetch outcomes (contract matrix)', () {
    test(
      '404 → failed(noRelease), classified, silent — names the defect',
      () async {
        final source = FakeVersionSource(const ReleaseNotFound());
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.2.4', build: '1');
        final events = <UpdateCheckResult>[];
        final sub = service.resultStream.listen(events.add);

        final outcome = await service.checkNow();
        await _settle();
        await sub.cancel();

        expect(outcome, isA<UpdateCheckFailed>());
        final failed = outcome as UpdateCheckFailed;
        expect(failed.reason, UpdateFailureReason.noRelease);
        expect(failed.retryAt, isNull);
        expect(events, isEmpty); // a failure never emits
        expect(service.lastResult, isNull); // and never reads as anything
      },
    );

    test('offline → failed(offline)', () async {
      final source = FakeVersionSource(const ReleaseOffline());
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      final outcome = await service.checkNow();

      expect(outcome, isA<UpdateCheckFailed>());
      expect(
        (outcome as UpdateCheckFailed).reason,
        UpdateFailureReason.offline,
      );
    });

    test('timeout → failed(timeout)', () async {
      final source = FakeVersionSource(const ReleaseTimedOut());
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      final outcome = await service.checkNow();

      expect(outcome, isA<UpdateCheckFailed>());
      expect(
        (outcome as UpdateCheckFailed).reason,
        UpdateFailureReason.timeout,
      );
    });

    test('unexpected status → failed(unexpected)', () async {
      final source = FakeVersionSource(
        const ReleaseUnexpected(statusCode: 503),
      );
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      final outcome = await service.checkNow();

      expect(outcome, isA<UpdateCheckFailed>());
      expect(
        (outcome as UpdateCheckFailed).reason,
        UpdateFailureReason.unexpected,
      );
    });

    test('rate-limited fetch result → failed(rateLimited, retryAt)', () async {
      final until = DateTime.now().add(const Duration(minutes: 30));
      final source = FakeVersionSource(ReleaseRateLimited(until));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      final outcome = await service.checkNow();

      expect(outcome, isA<UpdateCheckFailed>());
      final failed = outcome as UpdateCheckFailed;
      expect(failed.reason, UpdateFailureReason.rateLimited);
      expect(failed.retryAt, until);
    });
  });

  group('VersionCheckService scheduling/throttle', () {
    test(
      'resumed re-check is throttled: min 5 min between network calls',
      () async {
        final source = FakeVersionSource(_fetched('1.2.0'));
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');

        await service.init();
        await _settle();
        expect(source.calls, 1);

        service.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _settle();
        expect(source.calls, 1); // throttled — no network call
      },
    );

    test(
      'resumed re-check fires when the throttle window has passed',
      () async {
        final source = FakeVersionSource(_fetched('1.2.0'));
        final service = makeService(source: source, minInterval: Duration.zero);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');

        await service.init();
        await _settle();
        expect(source.calls, 1);

        service.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _settle();
        expect(source.calls, 2); // throttle window passed — re-check fired
      },
    );

    test('connectivity-restored hook triggers a throttled check', () async {
      final connectivity = FakeConnectivity();
      final source = FakeVersionSource(_fetched('1.2.0'));
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
      final source = FakeVersionSource(_fetched('1.2.0'));
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');

      await service.init();
      await _settle();
      expect(source.calls, 1);

      final outcome = await service.checkNow();
      expect(source.calls, 2);
      expect(outcome, isA<UpdateCheckCompleted>());
      expect(
        (outcome as UpdateCheckCompleted).result.level,
        UpdateLevel.available,
      );
    });

    test(
      'disabled build: no checks; checkNow reports skipped(nonRelease)',
      () async {
        final source = FakeVersionSource(_fetched('2.0.0'));
        final service = makeService(source: source, enabled: false);
        service.setCurrentVersionForTest(version: '1.0.0', build: '1');

        await service.init();
        await _settle();

        expect(source.calls, 0);

        final outcome = await service.checkNow();
        expect(outcome, isA<UpdateCheckSkipped>());
        expect(
          (outcome as UpdateCheckSkipped).reason,
          UpdateSkipReason.nonRelease,
        );
        expect(source.calls, 0); // still nothing was attempted
      },
    );

    test('unknown current version → skipped(versionUnknown)', () async {
      final source = FakeVersionSource(_fetched('2.0.0'));
      final service = makeService(source: source);

      final outcome = await service.checkNow();

      expect(outcome, isA<UpdateCheckSkipped>());
      expect(
        (outcome as UpdateCheckSkipped).reason,
        UpdateSkipReason.versionUnknown,
      );
      expect(source.calls, 0);
    });

    test(
      'init() survives PackageInfo failure (test hook injects version)',
      () async {
        // In the test environment PackageInfo.fromPlatform throws
        // (unmocked platform channel) — init must swallow it and still work
        // with the injected current version.
        final source = FakeVersionSource(_fetched('1.2.0'));
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.0.0', build: '1');

        await service.init();
        await _settle();

        expect(source.calls, 1);
        expect(service.lastResult!.level, UpdateLevel.available);
      },
    );

    test(
      'rate-limit backoff blocks checks until it passes; reason surfaced',
      () async {
        // Real GithubReleasesSource + MockClient returning 403 with a future
        // x-ratelimit-reset — exercises the service's backoff gate end to end:
        // fetch → no emit → no retry until the deadline passes, and a manual
        // check now REPORTS the rate limit instead of returning a stale result.
        var calls = 0;
        final resetEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        final source = GithubReleasesSource(
          client: MockClient((_) async {
            calls++;
            return http.Response(
              '{"message":"API rate limit exceeded"}',
              403,
              headers: {'x-ratelimit-reset': '$resetEpoch'},
            );
          }),
        );
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.0.0', build: '1');

        await service.init();
        await _settle();
        expect(service.lastResult, isNull); // 403 → no emit
        expect(calls, 1); // startup check only
        expect(source.backoffUntil, isNotNull);

        final outcome = await service.checkNow(); // blocked by the backoff gate
        expect(outcome, isA<UpdateCheckFailed>());
        final failed = outcome as UpdateCheckFailed;
        expect(failed.reason, UpdateFailureReason.rateLimited);
        expect(failed.retryAt, source.backoffUntil);
        expect(calls, 1); // no network call while rate-limited
      },
    );

    test('expired backoff allows the next check through', () async {
      var calls = 0;
      final source = GithubReleasesSource(
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response('{}', 429, headers: {'retry-after': '0'});
          }
          return http.Response(_ok200Body(), 200);
        }),
      );
      final service = makeService(source: source);
      service.setCurrentVersionForTest(version: '1.0.0', build: '1');

      await service.init();
      await _settle();
      expect(service.lastResult, isNull); // first attempt: rate-limited

      final outcome = await service.checkNow();
      expect(outcome, isA<UpdateCheckCompleted>());
      expect(calls, 2);
    });
  });

  group('in-flight join (stale-result fix)', () {
    test(
      'two concurrent checkNow() calls join the same in-flight outcome',
      () async {
        final source = ControlledSource();
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');

        await service.init(); // startup check now waiting on the completer
        expect(source.calls, 1);

        final first = service.checkNow();
        final second = service.checkNow();
        expect(identical(first, second), isTrue); // the same in-flight future
        expect(source.calls, 1); // joined — no second fetch, no stale return

        source.complete(_fetched('1.2.0'));

        final firstOutcome = await first;
        final secondOutcome = await second;
        expect(identical(firstOutcome, secondOutcome), isTrue);
        expect(firstOutcome, isA<UpdateCheckCompleted>());
        expect(service.lastResult!.level, UpdateLevel.available);

        // Once finished, a new checkNow starts a fresh check (no stale reuse).
        final third = await service.checkNow();
        expect(source.calls, 2);
        expect(third, isA<UpdateCheckCompleted>());
        expect(identical(third, firstOutcome), isFalse);
      },
    );
  });

  group('silence contract (automatic paths never emit failures)', () {
    test('startup + resumed failures emit nothing on resultStream', () async {
      final source = FakeVersionSource(const ReleaseOffline());
      final service = makeService(source: source, minInterval: Duration.zero);
      service.setCurrentVersionForTest(version: '1.1.0', build: '2');
      final events = <UpdateCheckResult>[];
      final sub = service.resultStream.listen(events.add);

      await service.init();
      await _settle();
      expect(source.calls, 1);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(source.calls, 2); // retried — and still silent

      await sub.cancel();
      expect(events, isEmpty);
      expect(service.lastResult, isNull);
    });

    test('resultStream broadcasts fresh completed outcomes only', () async {
      final source = FakeVersionSource(_fetched('1.2.0'));
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

    test(
      'cache: success is cached; a failed check never emits or clears it',
      () async {
        final source = FakeVersionSource(_fetched('1.2.0'));
        final service = makeService(source: source);
        service.setCurrentVersionForTest(version: '1.1.0', build: '2');

        await service.init();
        await _settle();
        expect(service.lastResult!.level, UpdateLevel.available);
        expect(service.cachedRelease!.version, '1.2.0');
        expect(service.lastSuccessfulCheckAt, isNotNull);

        // Simulate network failure — must never surface a dialog from stale data.
        source.result = const ReleaseOffline();
        final outcome = await service.checkNow(); // bypasses throttle
        expect(outcome, isA<UpdateCheckFailed>());
        expect(
          (outcome as UpdateCheckFailed).reason,
          UpdateFailureReason.offline,
        );
        expect(
          service.lastResult!.level,
          UpdateLevel.available,
        ); // state intact
        expect(service.cachedRelease!.version, '1.2.0'); // cache untouched
      },
    );
  });
}
