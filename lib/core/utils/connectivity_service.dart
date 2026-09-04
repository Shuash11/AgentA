import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  InternetStatus _lastStatus = InternetStatus.offline;
  final _statusController = StreamController<InternetStatus>.broadcast();
  StreamSubscription? _connectivitySubscription;

  Stream<InternetStatus> get statusStream => _statusController.stream;
  InternetStatus get lastStatus => _lastStatus;

  Future<void> init() async {
    final initialStatus = await checkInternetStatus();
    _lastStatus = initialStatus;
    _statusController.add(initialStatus);

    await _connectivitySubscription?.cancel();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) async {
      final newStatus = await checkInternetStatus();
      if (newStatus != _lastStatus) {
        _lastStatus = newStatus;
        _statusController.add(newStatus);
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _statusController.close();
  }

  Future<bool> isOnline() async {
    return (await checkInternetStatus()) == InternetStatus.online;
  }

  Future<InternetStatus> checkInternetStatus() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    final urls = [
      'https://www.google.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://clients3.google.com/generate_204',
    ];

    for (final url in urls) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        if (response.statusCode >= 200 && response.statusCode < 400) {
          client.close();
          return InternetStatus.online;
        }
      } catch (e) {
        continue;
      }
    }

    client.close();
    return InternetStatus.offline;
  }
}

enum InternetStatus {
  online,
  offline,
  limited,
}
