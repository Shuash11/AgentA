import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  static const Duration _connectionTimeout = Duration(seconds: 5);
  static const List<String> _probeUrls = [
    'https://www.google.com/generate_204',
    'https://connectivitycheck.gstatic.com/generate_204',
    'https://clients3.google.com/generate_204',
  ];

  final Connectivity _connectivity = Connectivity();
  HttpClient? _probeClient;

  InternetStatus _lastStatus = InternetStatus.offline;
  final _statusController = StreamController<InternetStatus>.broadcast();
  StreamSubscription? _connectivitySubscription;

  Stream<InternetStatus> get statusStream => _statusController.stream;
  InternetStatus get lastStatus => _lastStatus;

  /// Lazily-created, app-lifetime probe client. The connection timeout is
  /// set once — dart:io applies it to every connection initiated afterwards.
  HttpClient get _client =>
      _probeClient ??= HttpClient()..connectionTimeout = _connectionTimeout;

  Future<void> init() async {
    final initialStatus = await checkInternetStatus();
    _lastStatus = initialStatus;
    _statusController.add(initialStatus);

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      result,
    ) async {
      final newStatus = await checkInternetStatus();
      if (newStatus != _lastStatus) {
        _lastStatus = newStatus;
        _statusController.add(newStatus);
      }
    });
  }

  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_statusController.close());
    _probeClient?.close(force: true);
    _probeClient = null;
  }

  Future<bool> isOnline() async {
    return (await checkInternetStatus()) == InternetStatus.online;
  }

  Future<InternetStatus> checkInternetStatus() async {
    for (final url in _probeUrls) {
      try {
        final request = await _client.getUrl(Uri.parse(url));
        final response = await request.close();
        final statusCode = response.statusCode;
        // Read the body so the connection can return to the pool for reuse
        // (dart:io: an unread body leaks the connection).
        await response.drain<void>();

        if (statusCode >= 200 && statusCode < 400) {
          return InternetStatus.online;
        }
      } catch (e) {
        continue;
      }
    }

    return InternetStatus.offline;
  }
}

enum InternetStatus { online, offline, limited }
