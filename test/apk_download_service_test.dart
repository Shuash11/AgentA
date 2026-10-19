import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:aiproject/services/update/apk_download_service.dart';
import 'package:aiproject/services/update/install_failure_reason.dart';
import 'package:aiproject/services/update/version_source.dart';

RemoteRelease _release({
  String? url,
  int? size,
  String? sha,
  String version = '1.4.0',
}) => RemoteRelease(
  version: version,
  downloadUrl:
      url ??
      'https://github.com/Shuash11/AgentA/releases/download/v$version/AgentA-v$version.apk',
  assetSizeBytes: size,
  assetSha256: sha,
);

void main() {
  late Directory tempDir;
  final payload = utf8.encode('agent-a-test-apk-payload-bytes');
  final payloadSha = sha256.convert(payload).toString();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('apkdl_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  MockClient okClient({int? contentLength}) => MockClient.streaming(
    (request, bodyStream) async => http.StreamedResponse(
      Stream<List<int>>.fromIterable([
        payload.sublist(0, 10),
        payload.sublist(10),
      ]),
      200,
      contentLength: contentLength ?? payload.length,
    ),
  );

  ApkDownloadService serviceWith(http.Client client, {Duration? timeout}) =>
      ApkDownloadService(
        client: client,
        updatesDirectory: () async => tempDir,
        sendTimeout: timeout ?? const Duration(seconds: 30),
      );

  List<File> filesInTemp() =>
      tempDir.listSync().whereType<File>().toList(growable: false);

  test(
    'success: streams, verifies size+sha256, renames to the final file',
    () async {
      final service = serviceWith(okClient());
      final progress = <double>[];

      final result = await service.download(
        _release(size: payload.length, sha: payloadSha),
        onProgress: progress.add,
      );

      expect(result, isA<ApkDownloaded>());
      final downloaded = result as ApkDownloaded;
      expect(downloaded.bytesReceived, payload.length);
      expect(downloaded.sha256, payloadSha);
      expect(downloaded.filePath, endsWith('AgentA-1.4.0.apk'));
      expect(await File(downloaded.filePath).readAsBytes(), payload);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      // Only the final file remains — the .part file is gone.
      final files = filesInTemp();
      expect(files, hasLength(1));
      expect(p.basename(files.single.path), 'AgentA-1.4.0.apk');
    },
  );

  test('sha256 absent → downloads on size/TLS floor only', () async {
    final service = serviceWith(okClient());

    final result = await service.download(
      _release(size: payload.length),
      onProgress: (_) {},
    );

    expect(result, isA<ApkDownloaded>());
    expect((result as ApkDownloaded).sha256, payloadSha); // still computed
  });

  test(
    'size mismatch → sizeMismatch, partial file deleted, nothing remains',
    () async {
      final service = serviceWith(okClient());

      final result = await service.download(
        _release(size: payload.length + 5, sha: payloadSha),
        onProgress: (_) {},
      );

      expect(result, isA<ApkDownloadFailed>());
      expect(
        (result as ApkDownloadFailed).reason,
        InstallFailureReason.sizeMismatch,
      );
      expect(filesInTemp(), isEmpty);
    },
  );

  test('checksum mismatch → checksumMismatch, partial file deleted', () async {
    final service = serviceWith(okClient());

    final result = await service.download(
      _release(size: payload.length, sha: '0'.padRight(64, '0')),
      onProgress: (_) {},
    );

    expect(result, isA<ApkDownloadFailed>());
    expect(
      (result as ApkDownloadFailed).reason,
      InstallFailureReason.checksumMismatch,
    );
    expect(filesInTemp(), isEmpty);
  });

  test('non-https URL → download (TLS floor), no network call', () async {
    var calls = 0;
    final service = serviceWith(
      MockClient.streaming((request, bodyStream) async {
        calls++;
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
      }),
    );

    final result = await service.download(
      _release(url: 'http://insecure.example.com/x.apk'),
      onProgress: (_) {},
    );

    expect(result, isA<ApkDownloadFailed>());
    expect((result as ApkDownloadFailed).reason, InstallFailureReason.download);
    expect(calls, 0);
  });

  test('non-200 response → download failure', () async {
    final service = serviceWith(
      MockClient.streaming(
        (request, bodyStream) async =>
            http.StreamedResponse(const Stream<List<int>>.empty(), 404),
      ),
    );

    final result = await service.download(_release(), onProgress: (_) {});

    expect(result, isA<ApkDownloadFailed>());
    expect((result as ApkDownloadFailed).reason, InstallFailureReason.download);
  });

  test('transport error mid-download → network, partial cleaned', () async {
    final service = serviceWith(
      MockClient.streaming(
        (request, bodyStream) async =>
            throw const SocketException('connection reset'),
      ),
    );

    final result = await service.download(
      _release(size: payload.length),
      onProgress: (_) {},
    );

    expect(result, isA<ApkDownloadFailed>());
    expect((result as ApkDownloadFailed).reason, InstallFailureReason.network);
    expect(filesInTemp(), isEmpty);
  });

  test('storage failure (directory unavailable) → storage', () async {
    final service = ApkDownloadService(
      client: okClient(),
      updatesDirectory: () async => throw const FileSystemException('denied'),
    );

    final result = await service.download(
      _release(size: payload.length),
      onProgress: (_) {},
    );

    expect(result, isA<ApkDownloadFailed>());
    expect((result as ApkDownloadFailed).reason, InstallFailureReason.storage);
  });

  test('send timeout → timeout', () async {
    final service = serviceWith(
      MockClient.streaming((request, bodyStream) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
      }),
      timeout: const Duration(milliseconds: 20),
    );

    final result = await service.download(_release(), onProgress: (_) {});

    expect(result, isA<ApkDownloadFailed>());
    expect((result as ApkDownloadFailed).reason, InstallFailureReason.timeout);
  });

  test('cancel mid-download → cancelled, partial cleaned', () async {
    final controller = StreamController<List<int>>();
    final service = serviceWith(
      MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(
          controller.stream,
          200,
          contentLength: payload.length,
        ),
      ),
    );

    final future = service.download(
      _release(size: payload.length),
      onProgress: (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 20)); // attach

    controller.add(payload.sublist(0, 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.isDownloading, isTrue);

    service.cancel();
    controller.add(payload.sublist(10)); // after cancel — must be dropped
    await controller.close();

    final result = await future;
    expect(result, isA<ApkDownloadCancelled>());
    expect(filesInTemp(), isEmpty);
  });
}
