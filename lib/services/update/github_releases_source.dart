import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/semver.dart';
import 'version_source.dart';

/// [VersionSource] backed by the GitHub Releases API
/// (`GET /repos/Shuash11/AgentA/releases/latest`, see
/// [AppConfig.githubLatestReleaseUrl]).
///
/// Classification per `contracts/update-engine.yaml`:
///  - 8s timeout ([timeout]);
///  - 200 → parsed; unusable content (malformed JSON, non-map, draft,
///    prerelease, non-semver tag) → [ReleaseUnexpected] with `statusCode: 200`;
///  - 404 → [ReleaseNotFound] — covers a private/non-anonymous endpoint too;
///  - 403/429 → [ReleaseRateLimited], with the deadline from `retry-after`
///    (seconds) or `x-ratelimit-reset` (Unix epoch seconds); no request is
///    retried until it passes;
///  - transport errors (DNS/connect/TLS) → [ReleaseOffline]; the deadline
///    elapsed → [ReleaseTimedOut];
///  - anything else → [ReleaseUnexpected].
///
/// The unauthenticated GitHub rate limit is 60 req/hour/IP, which is why
/// [VersionCheckService] aggressively throttles and caches upstream.
class GithubReleasesSource implements VersionSource {
  final http.Client _client;
  final Duration timeout;

  DateTime? _backoffUntil;

  /// Rate-limit backoff deadline — null when not rate-limited.
  /// While this is in the future, no request may be retried.
  @override
  DateTime? get backoffUntil => _backoffUntil;

  /// [client] is injectable for unit tests (MockClient); defaults to a real
  /// [http.Client].
  GithubReleasesSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  @override
  Future<ReleaseFetchResult> fetchLatestRelease() async {
    final backoff = _backoffUntil;
    if (backoff != null && backoff.isAfter(DateTime.now())) {
      _log('[UpdateSource] skip — rate-limited until $backoff');
      return ReleaseRateLimited(backoff);
    }
    try {
      final response = await _client
          .get(
            Uri.parse(AppConfig.githubLatestReleaseUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'AgentA-UpdateCheck',
            },
          )
          .timeout(timeout);

      switch (response.statusCode) {
        case 200:
          _backoffUntil = null;
          return _parseRelease(response.body);
        case 404:
          // No releases published yet — or the endpoint is not anonymously
          // reachable (private repo): both are "no release info".
          _backoffUntil = null;
          return const ReleaseNotFound();
        case 403:
        case 429:
          return ReleaseRateLimited(_applyRateLimitBackoff(response.headers));
        default:
          _log('[UpdateSource] unexpected status ${response.statusCode}');
          return ReleaseUnexpected(statusCode: response.statusCode);
      }
    } on TimeoutException {
      _log('[UpdateSource] request timed out after ${timeout.inSeconds}s');
      return const ReleaseTimedOut();
    } on SocketException catch (e) {
      // DNS failure / connection refused / reset. package:http wraps these in
      // a ClientException that still implements SocketException.
      _log('[UpdateSource] offline (socket): $e');
      return const ReleaseOffline();
    } on HandshakeException catch (e) {
      _log('[UpdateSource] offline (TLS): $e');
      return const ReleaseOffline();
    } on HttpException catch (e) {
      _log('[UpdateSource] offline (http): $e');
      return const ReleaseOffline();
    } on http.ClientException catch (e) {
      _log('[UpdateSource] offline (client): $e');
      return const ReleaseOffline();
    } catch (e) {
      _log('[UpdateSource] unexpected fetch failure: $e');
      return const ReleaseUnexpected();
    }
  }

  /// 403/429: derive the backoff deadline from `retry-after` (seconds) or
  /// `x-ratelimit-reset` (Unix epoch seconds). No retry until it passes.
  /// Returns the applied deadline (always non-null).
  DateTime _applyRateLimitBackoff(Map<String, String> headers) {
    final now = DateTime.now();
    final retryAfter = int.tryParse(_header(headers, 'retry-after') ?? '');
    final resetEpoch = int.tryParse(
      _header(headers, 'x-ratelimit-reset') ?? '',
    );

    if (retryAfter != null) {
      _backoffUntil = now.add(Duration(seconds: retryAfter));
    } else if (resetEpoch != null) {
      _backoffUntil = DateTime.fromMillisecondsSinceEpoch(
        resetEpoch * 1000,
        isUtc: true,
      ).toLocal();
    } else {
      // Header missing/unparseable — fall back to the documented hourly
      // quota window so we never hammer a rate-limited endpoint.
      _backoffUntil = now.add(const Duration(hours: 1));
    }
    _log('[UpdateSource] rate-limited — backoff until $_backoffUntil');
    return _backoffUntil!;
  }

  /// Case-insensitive header lookup (http normalizes keys to lowercase,
  /// but stay defensive across clients).
  String? _header(Map<String, String> headers, String name) {
    final direct = headers[name];
    if (direct != null) return direct;
    for (final key in headers.keys) {
      if (key.toLowerCase() == name.toLowerCase()) return headers[key];
    }
    return null;
  }

  /// Parses a 200 body into [ReleaseFetched], or [ReleaseUnexpected]
  /// (`statusCode: 200`) when the content is not usable.
  ReleaseFetchResult _parseRelease(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      _log('[UpdateSource] release JSON decode failed: $e');
      return const ReleaseUnexpected(statusCode: 200);
    }
    if (json is! Map<String, dynamic>) {
      _log('[UpdateSource] release JSON is not an object');
      return const ReleaseUnexpected(statusCode: 200);
    }

    // Defensive re-check: /latest should never return drafts or prereleases,
    // but proxies/mirrors or API changes make this worth enforcing.
    if (json['draft'] == true || json['prerelease'] == true) {
      _log('[UpdateSource] latest release is draft/prerelease — ignoring');
      return const ReleaseUnexpected(statusCode: 200);
    }

    final tagName = json['tag_name'];
    final version = tagName is String ? SemVer.tryParseTag(tagName) : null;
    if (version == null) {
      _log(
        '[UpdateSource] tag_name "${tagName ?? ''}" is not strict semver — ignoring',
      );
      return const ReleaseUnexpected(statusCode: 200);
    }

    final notes = (json['body'] as String?)?.trim();
    final releaseUrl = json['html_url'] as String?;
    final publishedRaw = json['published_at'];
    final publishedAt = publishedRaw is String
        ? DateTime.tryParse(publishedRaw)
        : null;

    final apk = _parseApkAsset(json);

    return ReleaseFetched(
      RemoteRelease(
        version: version.toString(),
        minVersion: _parseMinVersion(notes),
        downloadUrl: apk.url,
        assetSizeBytes: apk.size,
        assetSha256: apk.sha256,
        releaseUrl: releaseUrl,
        notes: notes,
        publishedAt: publishedAt,
      ),
    );
  }

  /// `min-version: x.y.z` marker line in the release body.
  /// A malformed marker is treated as "no forced update" (never force on junk).
  String? _parseMinVersion(String? body) {
    if (body == null || body.isEmpty) return null;
    const marker = 'min-version:';
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith(marker)) continue;
      final value = trimmed.substring(marker.length).trim();
      if (SemVer.tryParse(value) != null) return value;
      _log(
        '[UpdateSource] malformed min-version marker "$value" — treating as none',
      );
      return null;
    }
    return null;
  }

  /// First `*.apk` asset: browser_download_url, `size` and `digest` for the
  /// integrity floor (contract §1, v1.1.1). ASSET-ONLY (P7 F1): when no
  /// `.apk` asset exists the URL is null — the in-app download never falls
  /// back to the release page. An unusable digest is treated as absent —
  /// never as a failure.
  ({String? url, int? size, String? sha256}) _parseApkAsset(
    Map<String, dynamic> json,
  ) {
    final assets = json['assets'];
    if (assets is! List) return (url: null, size: null, sha256: null);
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String &&
          name.toLowerCase().endsWith('.apk') &&
          url is String &&
          url.isNotEmpty) {
        return (
          url: url,
          size: _parseAssetSize(asset['size']),
          sha256: _parseAssetDigest(asset['digest']),
        );
      }
    }
    return (url: null, size: null, sha256: null);
  }

  int? _parseAssetSize(dynamic raw) {
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0) return raw.toInt();
    return null;
  }

  /// A `sha256:<64 hex>` digest string → the lowercase hex, else null
  /// (checksum skipped — never a failure).
  String? _parseAssetDigest(dynamic raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(raw.trim());
    if (match == null) {
      _log('[UpdateSource] unusable asset digest "$raw" — checksum skipped');
      return null;
    }
    return match.group(1)!.toLowerCase();
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
