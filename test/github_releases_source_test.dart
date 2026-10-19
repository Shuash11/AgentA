import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aiproject/services/update/github_releases_source.dart';
import 'package:aiproject/services/update/version_source.dart';

http.Response _releaseResponse({Map<String, dynamic>? overrides}) {
  final body = <String, dynamic>{
    'tag_name': 'v1.2.0',
    'draft': false,
    'prerelease': false,
    'html_url': 'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0',
    'body': 'Release notes\nmin-version: 1.0.0\n',
    'published_at': '2026-09-20T10:00:00Z',
    'assets': [
      {
        'name': 'AgentA-v1.2.0.apk',
        'browser_download_url':
            'https://github.com/Shuash11/AgentA/releases/download/v1.2.0/AgentA-v1.2.0.apk',
      },
      {
        'name': 'checksums.txt',
        'browser_download_url': 'https://example.com/checksums.txt',
      },
    ],
  };
  if (overrides != null) body.addAll(overrides);
  return http.Response(jsonEncode(body), 200);
}

/// Unwraps a [ReleaseFetched] — fails the test on any other result.
RemoteRelease _releaseOf(ReleaseFetchResult result) =>
    (result as ReleaseFetched).release;

void main() {
  group('GithubReleasesSource (GitHub API)', () {
    test('200 parses the JSON subset per contract', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => _releaseResponse()),
      );

      final release = _releaseOf(await source.fetchLatestRelease());

      expect(release.version, '1.2.0'); // 'v'-stripped, strict semver
      expect(release.minVersion, '1.0.0'); // from body marker line
      expect(
        release.downloadUrl,
        'https://github.com/Shuash11/AgentA/releases/download/v1.2.0/AgentA-v1.2.0.apk',
      );
      expect(
        release.releaseUrl,
        'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0',
      );
      expect(release.notes, 'Release notes\nmin-version: 1.0.0');
      expect(release.publishedAt, isNotNull);
      expect(source.backoffUntil, isNull);
    });

    test('real v1.2.5 payload shape → ReleaseFetched (P1 regression)', () async {
      // The shape verified in the P1 diagnosis (authenticated read of the real
      // release): tag v1.2.5, not draft/prerelease, no min-version marker,
      // one APK asset.
      final source = GithubReleasesSource(
        client: MockClient(
          (_) async => _releaseResponse(
            overrides: {
              'tag_name': 'v1.2.5',
              'body': 'Bug fixes and improvements',
              'assets': [
                {
                  'name': 'AgentA-v1.2.5.apk',
                  'browser_download_url':
                      'https://github.com/Shuash11/AgentA/releases/download/v1.2.5/AgentA-v1.2.5.apk',
                },
              ],
            },
          ),
        ),
      );

      final release = _releaseOf(await source.fetchLatestRelease());

      expect(release.version, '1.2.5');
      expect(release.minVersion, isNull);
      expect(release.downloadUrl, endsWith('AgentA-v1.2.5.apk'));
    });

    test(
      'no *.apk asset → downloadUrl null, releaseUrl carries the page',
      () async {
        final source = GithubReleasesSource(
          client: MockClient(
            (_) async => _releaseResponse(
              overrides: {
                'assets': [
                  {
                    'name': 'checksums.txt',
                    'browser_download_url': 'https://example.com/checksums.txt',
                  },
                ],
              },
            ),
          ),
        );

        final release = _releaseOf(await source.fetchLatestRelease());

        // Asset-only (P7 F1): the in-app flow must never target a non-APK page.
        expect(release.downloadUrl, isNull);
        expect(
          release.releaseUrl,
          'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0',
        );
      },
    );

    test(
      'draft/prerelease releases → ReleaseUnexpected(200) (defensive)',
      () async {
        final draftSource = GithubReleasesSource(
          client: MockClient(
            (_) async => _releaseResponse(overrides: {'draft': true}),
          ),
        );
        final preSource = GithubReleasesSource(
          client: MockClient(
            (_) async => _releaseResponse(overrides: {'prerelease': true}),
          ),
        );

        final draftResult = await draftSource.fetchLatestRelease();
        final preResult = await preSource.fetchLatestRelease();

        expect(draftResult, isA<ReleaseUnexpected>());
        expect(preResult, isA<ReleaseUnexpected>());
        expect((draftResult as ReleaseUnexpected).statusCode, 200);
        expect((preResult as ReleaseUnexpected).statusCode, 200);
      },
    );

    test('non-semver tag_name → ReleaseUnexpected(200)', () async {
      final source = GithubReleasesSource(
        client: MockClient(
          (_) async => _releaseResponse(overrides: {'tag_name': 'latest'}),
        ),
      );

      final result = await source.fetchLatestRelease();

      expect(result, isA<ReleaseUnexpected>());
      expect((result as ReleaseUnexpected).statusCode, 200);
    });

    test(
      'malformed min-version marker → treated as no forced update',
      () async {
        final source = GithubReleasesSource(
          client: MockClient(
            (_) async =>
                _releaseResponse(overrides: {'body': 'min-version: banana\n'}),
          ),
        );

        final release = _releaseOf(await source.fetchLatestRelease());

        expect(release.minVersion, isNull);
      },
    );

    test('404 → ReleaseNotFound (classified), no backoff', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response('Not Found', 404)),
      );

      final result = await source.fetchLatestRelease();

      expect(result, isA<ReleaseNotFound>());
      expect(source.backoffUntil, isNull);
    });

    test(
      '403 → ReleaseRateLimited with x-ratelimit-reset; never retries until it passes',
      () async {
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

        final first = await source.fetchLatestRelease();
        expect(first, isA<ReleaseRateLimited>());
        final retryAt = (first as ReleaseRateLimited).retryAt;
        expect(retryAt.isAfter(DateTime.now()), isTrue);
        expect(source.backoffUntil, isNotNull);
        expect(retryAt, source.backoffUntil);

        // Second call refused by the source's own backoff gate.
        final second = await source.fetchLatestRelease();
        expect(second, isA<ReleaseRateLimited>());
        expect((second as ReleaseRateLimited).retryAt, retryAt);
        expect(calls, 1);
      },
    );

    test('429 → backoffUntil from retry-after', () async {
      final source = GithubReleasesSource(
        client: MockClient(
          (_) async => http.Response(
            '{"message":"Too Many Requests"}',
            429,
            headers: {'retry-after': '120'},
          ),
        ),
      );

      final result = await source.fetchLatestRelease();
      expect(result, isA<ReleaseRateLimited>());
      expect(source.backoffUntil, isNotNull);

      // Skew-tolerant window — the source timestamps with its own clock read.
      final now = DateTime.now();
      expect(
        source.backoffUntil!.isAfter(now.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(
        source.backoffUntil!.isBefore(now.add(const Duration(seconds: 125))),
        isTrue,
      );
    });

    test('expired backoff allows retry and 200 clears the backoff', () async {
      var calls = 0;
      final source = GithubReleasesSource(
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response('{}', 429, headers: {'retry-after': '0'});
          }
          return _releaseResponse();
        }),
      );

      final first = await source.fetchLatestRelease(); // 429 → backoff set
      expect(first, isA<ReleaseRateLimited>());
      expect(source.backoffUntil, isNotNull);

      final second = await source.fetchLatestRelease(); // retry allowed
      final release = _releaseOf(second);
      expect(release.version, '1.2.0');
      expect(source.backoffUntil, isNull); // 200 cleared it
      expect(calls, 2);
    });

    test('5xx / other status → ReleaseUnexpected(statusCode)', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response('oops', 503)),
      );

      final result = await source.fetchLatestRelease();

      expect(result, isA<ReleaseUnexpected>());
      expect((result as ReleaseUnexpected).statusCode, 503);
      expect(source.backoffUntil, isNull);
    });

    test(
      'transport failures → ReleaseOffline (socket/TLS/http/client)',
      () async {
        final socketSource = GithubReleasesSource(
          client: MockClient(
            (_) async => throw SocketException('Failed host lookup'),
          ),
        );
        final tlsSource = GithubReleasesSource(
          client: MockClient(
            (_) async => throw HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          ),
        );
        final httpSource = GithubReleasesSource(
          client: MockClient((_) async => throw HttpException('bad response')),
        );
        final clientSource = GithubReleasesSource(
          client: MockClient(
            (_) async => throw http.ClientException(
              'Connection closed before full header was received',
            ),
          ),
        );

        expect(await socketSource.fetchLatestRelease(), isA<ReleaseOffline>());
        expect(await tlsSource.fetchLatestRelease(), isA<ReleaseOffline>());
        expect(await httpSource.fetchLatestRelease(), isA<ReleaseOffline>());
        expect(await clientSource.fetchLatestRelease(), isA<ReleaseOffline>());
        expect(socketSource.backoffUntil, isNull);
      },
    );

    test('timeout (8s deadline) → ReleaseTimedOut', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return _releaseResponse();
        }),
        timeout: const Duration(milliseconds: 30),
      );

      expect(await source.fetchLatestRelease(), isA<ReleaseTimedOut>());
    });

    test('unknown exception → ReleaseUnexpected (statusCode null)', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => throw Exception('boom')),
      );

      final result = await source.fetchLatestRelease();

      expect(result, isA<ReleaseUnexpected>());
      expect((result as ReleaseUnexpected).statusCode, isNull);
      expect(source.backoffUntil, isNull);
    });

    test('malformed JSON → ReleaseUnexpected(200)', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      final result = await source.fetchLatestRelease();

      expect(result, isA<ReleaseUnexpected>());
      expect((result as ReleaseUnexpected).statusCode, 200);
    });

    test('non-map JSON → ReleaseUnexpected(200)', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response('[1,2,3]', 200)),
      );

      final result = await source.fetchLatestRelease();

      expect(result, isA<ReleaseUnexpected>());
      expect((result as ReleaseUnexpected).statusCode, 200);
    });

    test('asset size + digest parsed per contract v1.1.0 (§1)', () async {
      final source = GithubReleasesSource(
        client: MockClient(
          (_) async => _releaseResponse(
            overrides: {
              'assets': [
                {
                  'name': 'AgentA-v1.2.5.apk',
                  'browser_download_url':
                      'https://github.com/Shuash11/AgentA/releases/download/v1.2.5/AgentA-v1.2.5.apk',
                  'size': 183012343,
                  'digest':
                      'sha256:EB7643C359BC73B3257B49C69425242C1C443DCC17C3AD5261458FEFA1D4D4BD',
                },
              ],
            },
          ),
        ),
      );

      final release = _releaseOf(await source.fetchLatestRelease());

      expect(release.assetSizeBytes, 183012343);
      // 'sha256:' stripped, hex normalized to lowercase.
      expect(
        release.assetSha256,
        'eb7643c359bc73b3257b49c69425242c1c443dcc17c3ad5261458fefa1d4d4bd',
      );
    });

    test('unusable digest → treated as absent (checksum skipped)', () async {
      final source = GithubReleasesSource(
        client: MockClient(
          (_) async => _releaseResponse(
            overrides: {
              'assets': [
                {
                  'name': 'AgentA-v1.2.5.apk',
                  'browser_download_url':
                      'https://github.com/Shuash11/AgentA/releases/download/v1.2.5/AgentA-v1.2.5.apk',
                  'size': 10,
                  'digest': 'md5:abc',
                },
              ],
            },
          ),
        ),
      );

      final release = _releaseOf(await source.fetchLatestRelease());

      expect(release.assetSizeBytes, 10);
      expect(release.assetSha256, isNull);
    });
  });
}
