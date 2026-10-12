import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/semver.dart';
import 'version_source.dart';

/// [VersionSource] backed by the GitHub Releases API
/// (`GET /repos/Shuash11/AgentA/releases/latest`, see
/// [AppConfig.githubLatestReleaseUrl]).
///
/// Handling per contract:
///  - 8s timeout ([timeout]);
///  - 200 → parses the JSON subset, defensively re-checking
///    `draft == false && prerelease == false` and strict semver `tag_name`;
///  - 404 → null (no releases published yet — a valid "nothing to see");
///  - 403/429 → parses `x-ratelimit-reset` / `retry-after` and exposes a
///    [backoffUntil] deadline; no request is retried until it passes;
///  - network errors → silent failure (debug log only, returns null).
///
/// The unauthenticated GitHub rate limit is 60 req/hour/IP, which is why
/// [VersionCheckService] aggressively throttles and caches upstream.
class GithubReleasesSource implements VersionSource {
  final http.Client _client;
  final Duration timeout;

  DateTime? _backoffUntil;

  /// Rate-limit backoff deadline — null when not rate-limited.
  /// While this is in the future, no request may be retried.
  DateTime? get backoffUntil => _backoffUntil;

  /// [client] is injectable for unit tests (MockClient); defaults to a real
  /// [http.Client].
  GithubReleasesSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  @override
  Future<RemoteRelease?> fetchLatestRelease() async {
    if (_isBackedOff) {
      _log('[UpdateSource] skip — rate-limited until $_backoffUntil');
      return null;
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
          // No releases published yet — a valid "nothing to see" answer.
          _backoffUntil = null;
          return null;
        case 403:
        case 429:
          _applyRateLimitBackoff(response.headers);
          return null;
        default:
          _log('[UpdateSource] unexpected status ${response.statusCode}');
          return null;
      }
    } catch (e) {
      // Network errors, timeouts, malformed JSON → silent failure.
      _log('[UpdateSource] fetch failed (silent): $e');
      return null;
    }
  }

  bool get _isBackedOff =>
      _backoffUntil != null && _backoffUntil!.isAfter(DateTime.now());

  /// 403/429: derive the backoff deadline from `retry-after` (seconds) or
  /// `x-ratelimit-reset` (Unix epoch seconds). No retry until it passes.
  void _applyRateLimitBackoff(Map<String, String> headers) {
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

  RemoteRelease? _parseRelease(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      _log('[UpdateSource] release JSON decode failed: $e');
      return null;
    }
    if (json is! Map<String, dynamic>) return null;

    // Defensive re-check: /latest should never return drafts or prereleases,
    // but proxies/mirrors or API changes make this worth enforcing.
    if (json['draft'] == true || json['prerelease'] == true) {
      _log('[UpdateSource] latest release is draft/prerelease — ignoring');
      return null;
    }

    final tagName = json['tag_name'];
    final version = tagName is String ? SemVer.tryParseTag(tagName) : null;
    if (version == null) {
      _log(
        '[UpdateSource] tag_name "${tagName ?? ''}" is not strict semver — ignoring',
      );
      return null;
    }

    final notes = (json['body'] as String?)?.trim();
    final releaseUrl = json['html_url'] as String?;
    final publishedRaw = json['published_at'];
    final publishedAt = publishedRaw is String
        ? DateTime.tryParse(publishedRaw)
        : null;

    return RemoteRelease(
      version: version.toString(),
      minVersion: _parseMinVersion(notes),
      downloadUrl: _parseDownloadUrl(json, releaseUrl),
      releaseUrl: releaseUrl,
      notes: notes,
      publishedAt: publishedAt,
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

  /// First `*.apk` asset's browser_download_url; falls back to [fallback].
  String? _parseDownloadUrl(Map<String, dynamic> json, String? fallback) {
    final assets = json['assets'];
    if (assets is! List) return fallback;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String &&
          name.toLowerCase().endsWith('.apk') &&
          url is String &&
          url.isNotEmpty) {
        return url;
      }
    }
    return fallback;
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}
