import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';

class KaggleDownloadService {
  static const String _baseUrl = 'https://www.kaggle.com/api/v1';
  
  final String username;
  final String key;
  
  KaggleDownloadService({required this.username, required this.key});
  
  String _getAuthHeader() {
    final creds = '$username:$key';
    final encoded = base64Encode(utf8.encode(creds));
    return 'Basic $encoded';
  }
  
  Future<String?> getModelDownloadUrl({
    required String ownerSlug,
    required String modelSlug,
    required String framework,
    required String instanceSlug,
  }) async {
    try {
      // Get model instance files
      final url = '$_baseUrl/models/$ownerSlug/$modelSlug/versions/$framework/$instanceSlug/files';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': _getAuthHeader()},
      );
      
      _log('Kaggle API Response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final files = jsonDecode(response.body);
        if (files is List && files.isNotEmpty) {
          // Find the .task file
          for (var file in files) {
            final fileName = file['name'] as String?;
            if (fileName != null && fileName.endsWith('.task')) {
              return file['url'];
            }
          }
        }
      }
      
      _log('Kaggle API Error: ${response.body}');
      return null;
    } catch (e) {
      _log('Kaggle API Exception: $e');
      return null;
    }
  }
  Future<String?> downloadModel({
    required String modelRef,
    required String framework,
    required String instanceSlug,
    Function(double)? onProgress,
  }) async {
    try {
      // Parse model ref (e.g., "google/gemma-3/flax")
      final parts = modelRef.split('/');
      if (parts.length < 2) return null;
      final ownerSlug = parts[0];
      final modelSlug = parts[1];
      
      // Get the download URL
      final downloadUrl = await getModelDownloadUrl(
        ownerSlug: ownerSlug,
        modelSlug: modelSlug,
        framework: framework,
        instanceSlug: instanceSlug,
      );
      
      if (downloadUrl == null) {
        _log('Failed to get download URL from Kaggle');
        return null;
      }
      
      // Download the file
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/models');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      
      final filePath = '${modelDir.path}/gemma3-1b-it-int4.task';

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(downloadUrl));
        final streamedResponse = await client.send(request);

        final totalBytes = streamedResponse.contentLength ?? 0;
        var receivedBytes = 0;

        final file = File(filePath);
        final sink = file.openWrite();

        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (onProgress != null && totalBytes > 0) {
            onProgress(receivedBytes / totalBytes * 100);
          }
        }

        await sink.close();
        _log('Model downloaded to: $filePath');
        return filePath;
      } catch (e) {
        _log('Kaggle Download Exception: $e');
        return null;
      } finally {
        client.close();
      }
    } catch (e) {
      _log('Kaggle Download Exception: $e');
      return null;
    }
  }
  
  void _log(String message) {
    // ignore: avoid_print
    print('KaggleDownloadService: $message');
  }
}

KaggleDownloadService createKaggleService() {
  return KaggleDownloadService(
    username: AppConfig.kaggleUsername,
    key: AppConfig.kaggleKey,
  );
}