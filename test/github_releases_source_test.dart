import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aiproject/services/update/github_releases_source.dart';

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

void main() {
  group('GithubReleasesSource (GitHub API)', () {
    test('200 parses the JSON subset per contract', () async {
      final source =
          GithubReleasesSource(client: MockClient((_) async => _releaseResponse()));

      final release = await source.fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.version, '1.2.0'); // 'v'-stripped, strict semver
      expect(release.minVersion, '1.0.0'); // from body marker line
      expect(release.downloadUrl,
          'https://github.com/Shuash11/AgentA/releases/download/v1.2.0/AgentA-v1.2.0.apk');
      expect(release.releaseUrl,
          'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0');
      expect(release.notes, 'Release notes\nmin-version: 1.0.0');
      expect(release.publishedAt, isNotNull);
      expect(source.backoffUntil, isNull);
    });

    test('downloadUrl falls back to html_url when no *.apk asset', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => _releaseResponse(overrides: {
              'assets': [
                {
                  'name': 'checksums.txt',
                  'browser_download_url': 'https://example.com/checksums.txt',
                },
              ],
            })),
      );

      final release = await source.fetchLatestRelease();

      expect(release!.downloadUrl,
          'https://github.com/Shuash11/AgentA/releases/tag/v1.2.0');
    });

    test('draft/prerelease releases are ignored (defensive re-check)', () async {
      final draftSource = GithubReleasesSource(
        client: MockClient((_) async => _releaseResponse(overrides: {'draft': true})),
      );
      final preSource = GithubReleasesSource(
        client:
            MockClient((_) async => _releaseResponse(overrides: {'prerelease': true})),
      );

      expect(await draftSource.fetchLatestRelease(), isNull);
      expect(await preSource.fetchLatestRelease(), isNull);
    });

    test('non-semver tag_name → null', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => _releaseResponse(overrides: {'tag_name': 'latest'})),
      );

      expect(await source.fetchLatestRelease(), isNull);
    });

    test('malformed min-version marker → treated as no forced update', () async {
      final source = GithubReleasesSource(
        client: MockClient(
            (_) async => _releaseResponse(overrides: {'body': 'min-version: banana\n'})),
      );

      final release = await source.fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.minVersion, isNull);
    });

    test('404 → null, no backoff', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response('Not Found', 404)),
      );

      expect(await source.fetchLatestRelease(), isNull);
      expect(source.backoffUntil, isNull);
    });

    test('403 → backoffUntil from x-ratelimit-reset; never retries until it passes',
        () async {
      var calls = 0;
      final resetEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      final source = GithubReleasesSource(
        client: MockClient((_) async {
          calls++;
          return http.Response('{"message":"API rate limit exceeded"}', 403,
              headers: {'x-ratelimit-reset': '$resetEpoch'});
        }),
      );

      expect(await source.fetchLatestRelease(), isNull);
      expect(source.backoffUntil, isNotNull);
      expect(source.backoffUntil!.isAfter(DateTime.now()), isTrue);

      // Second call refused by the source's own backoff gate.
      expect(await source.fetchLatestRelease(), isNull);
      expect(calls, 1);
    });

    test('429 → backoffUntil from retry-after', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response(
              '{"message":"Too Many Requests"}',
              429,
              headers: {'retry-after': '120'},
            )),
      );

      expect(await source.fetchLatestRelease(), isNull);

      expect(source.backoffUntil, isNotNull);
      // Skew-tolerant window — the source timestamps with its own clock read.
      final now = DateTime.now();
      expect(
          source.backoffUntil!.isAfter(now.subtract(const Duration(seconds: 5))),
          isTrue);
      expect(source.backoffUntil!.isBefore(now.add(const Duration(seconds: 125))),
          isTrue);
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

      expect(await source.fetchLatestRelease(), isNull); // 429 → backoff set
      expect(source.backoffUntil, isNotNull);

      final release = await source.fetchLatestRelease(); // retry allowed
      expect(release, isNotNull);
      expect(release!.version, '1.2.0');
      expect(source.backoffUntil, isNull); // 200 cleared it
      expect(calls, 2);
    });

    test('network errors → silent failure (null)', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => throw Exception('boom')),
      );

      expect(await source.fetchLatestRelease(), isNull);
      expect(source.backoffUntil, isNull);
    });

    test('malformed JSON → silent failure (null)', () async {
      final source = GithubReleasesSource(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      expect(await source.fetchLatestRelease(), isNull);
    });
  });
}
