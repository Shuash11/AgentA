import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'install_failure_reason.dart';
import 'version_source.dart';

/// Classified outcome of [ApkDownloadService.download] (contract §4).
sealed class ApkDownloadResult {
  const ApkDownloadResult();
}

/// A verified APK at [filePath] — renamed from the `.part` file only after
/// size/checksum verification (a partial download is never handed onward).
final class ApkDownloaded extends ApkDownloadResult {
  final String filePath;
  final int bytesReceived;
  final String sha256;

  const ApkDownloaded({
    required this.filePath,
    required this.bytesReceived,
    required this.sha256,
  });
}

/// The download was cancelled by the user (or superseded).
final class ApkDownloadCancelled extends ApkDownloadResult {
  const ApkDownloadCancelled();
}

/// The download failed; [reason] is from the contract's shared enum.
final class ApkDownloadFailed extends ApkDownloadResult {
  final InstallFailureReason reason;

  const ApkDownloadFailed(this.reason);
}

/// Downloads the release APK to app-internal storage and verifies it.
///
/// Contract: `contracts/update-engine.yaml` §4 (`install_flow.download`).
///  - storage: `getApplicationSupportDirectory()/updates/AgentA-<v>.apk`
///    (app-internal files dir — no runtime storage permission; written as
///    `.part`, renamed only after verification — atomicity);
///  - integrity: https-only URL (TLS floor), size cross-check against
///    `assetSizeBytes`/Content-Length, SHA-256 against the API digest when
///    present; the partial file is deleted on every failure/cancel;
///  - cancellation: [cancel] aborts the transfer; the pending [download]
///    future resolves as [ApkDownloadCancelled].
///
/// Never throws — every outcome is classified. Both the HTTP client and the
/// updates-directory resolver are injectable for hermetic tests.
class ApkDownloadService {
  ApkDownloadService({
    http.Client? client,
    Future<Directory> Function()? updatesDirectory,
    this.sendTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _updatesDirectory = updatesDirectory ?? _defaultUpdatesDirectory;

  final http.Client _client;
  final Future<Directory> Function() _updatesDirectory;

  /// Deadline for the response headers ([http.Client.send]); injectable for
  /// timeout-path tests. Mirrors `GithubReleasesSource.timeout`.
  final Duration sendTimeout;

  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _pending;
  bool _cancelled = false;

  static Future<Directory> _defaultUpdatesDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'updates'));
  }

  /// True while a download is in flight.
  bool get isDownloading => _pending != null && !_pending!.isCompleted;

  /// Aborts the in-flight download, if any. The pending [download] future
  /// resolves as [ApkDownloadCancelled]; the partial file is deleted.
  void cancel() {
    _cancelled = true;
    unawaited(_subscription?.cancel());
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Downloads [release]'s APK. [onProgress] receives 0.0..1.0 (0.0 until
  /// completion when no total is known).
  Future<ApkDownloadResult> download(
    RemoteRelease release, {
    required void Function(double progress) onProgress,
  }) async {
    _cancelled = false;
    _subscription = null;
    _pending = null;

    final uri = Uri.tryParse(release.downloadUrl ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _log('[ApkDownload] rejected non-https/malformed download URL');
      return const ApkDownloadFailed(InstallFailureReason.download);
    }
    if (!isWritableVersion(release.version)) {
      return const ApkDownloadFailed(InstallFailureReason.download);
    }

    File? part;
    IOSink? sink;
    try {
      final dir = await _updatesDirectory();
      await dir.create(recursive: true);
      await _pruneDirectory(dir);

      part = File(p.join(dir.path, 'AgentA-${release.version}.apk.part'));
      final finalFile = File(p.join(dir.path, 'AgentA-${release.version}.apk'));

      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'AgentA-UpdateCheck';
      final response = await _client.send(request).timeout(sendTimeout);
      if (response.statusCode != 200) {
        _log('[ApkDownload] unexpected status ${response.statusCode}');
        return const ApkDownloadFailed(InstallFailureReason.download);
      }

      final expectedSize =
          release.assetSizeBytes ?? response.contentLength?.toInt();

      final digestSink = _DigestSink();
      final hashInput = sha256.startChunkedConversion(digestSink);
      sink = part.openWrite();
      var received = 0;

      final completed = Completer<void>();
      _pending = completed;
      _subscription = response.stream.listen(
        (chunk) {
          if (_cancelled) return;
          received += chunk.length;
          hashInput.add(chunk);
          sink!.add(chunk);
          final total = expectedSize;
          onProgress(
            total == null || total <= 0
                ? 0.0
                : (received / total).clamp(0.0, 1.0),
          );
        },
        onError: (Object e, StackTrace s) {
          if (!completed.isCompleted) completed.completeError(e, s);
        },
        onDone: () {
          if (!completed.isCompleted) completed.complete();
        },
        cancelOnError: true,
      );

      try {
        await completed.future;
      } finally {
        _pending = null;
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (_cancelled) {
        await _deleteQuietly(part);
        return const ApkDownloadCancelled();
      }

      hashInput.close();
      final actualSha256 = digestSink.digest.toString();

      if (expectedSize != null &&
          expectedSize > 0 &&
          received != expectedSize) {
        _log(
          '[ApkDownload] size mismatch: got $received, expected $expectedSize',
        );
        await _deleteQuietly(part);
        return const ApkDownloadFailed(InstallFailureReason.sizeMismatch);
      }

      final expectedSha = release.assetSha256;
      if (expectedSha != null && actualSha256 != expectedSha) {
        _log('[ApkDownload] sha256 mismatch — expected $expectedSha');
        await _deleteQuietly(part);
        return const ApkDownloadFailed(InstallFailureReason.checksumMismatch);
      }

      final renamed = await part.rename(finalFile.path);
      onProgress(1.0);
      _log('[ApkDownload] verified $received bytes → ${renamed.path}');
      return ApkDownloaded(
        filePath: renamed.path,
        bytesReceived: received,
        sha256: actualSha256,
      );
    } on TimeoutException {
      _log('[ApkDownload] timed out');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.timeout);
    } on FileSystemException catch (e) {
      _log('[ApkDownload] storage failure: $e');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.storage);
    } on SocketException catch (e) {
      _log('[ApkDownload] offline (socket): $e');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.network);
    } on HandshakeException catch (e) {
      _log('[ApkDownload] offline (TLS): $e');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.network);
    } on HttpException catch (e) {
      _log('[ApkDownload] offline (http): $e');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.network);
    } on http.ClientException catch (e) {
      _log('[ApkDownload] offline (client): $e');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.network);
    } catch (e) {
      _log('[ApkDownload] unexpected failure: $e');
      await _deleteQuietly(part);
      return const ApkDownloadFailed(InstallFailureReason.unknown);
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // Best-effort — the outcome was already classified.
      }
    }
  }

  /// The final filename embeds the version — restrict to a safe, semver-like
  /// token so a hostile release string can never traverse paths.
  static bool isWritableVersion(String version) =>
      RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{0,31}$').hasMatch(version);

  Future<void> _pruneDirectory(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File) await _deleteQuietly(entity);
      }
    } catch (e) {
      _log('[ApkDownload] prune failed (non-fatal): $e');
    }
  }

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log('[ApkDownload] cleanup failed (non-fatal): $e');
    }
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}

/// Minimal [Sink] collecting the single [Digest] `crypto` emits on close.
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest {
    final value = _digest;
    if (value == null) throw StateError('digest unavailable before close()');
    return value;
  }

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
