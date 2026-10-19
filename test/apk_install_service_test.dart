import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/services/update/apk_install_service.dart';
import 'package:aiproject/services/update/install_failure_reason.dart';

const String _channelName = 'com.agenta.agenta/apk_install';
const MethodChannel _channel = MethodChannel(_channelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApkInstallService service;
  final recorded = <String, Object?>{};

  setUp(() {
    recorded.clear();
    service = ApkInstallService();
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel({
    bool canInstall = true,
    Object? startError,
    bool recordStart = true,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'canInstall':
              return canInstall;
            case 'startInstall':
              if (recordStart) {
                recorded.addAll(
                  (call.arguments as Map).cast<String, Object?>(),
                );
              }
              if (startError != null) throw startError;
              return null;
            case 'openInstallPermissionSettings':
              recorded['settingsOpened'] = true;
              return null;
          }
          return null;
        });
  }

  Future<void> nativeEvent(String method, Map<String, Object?> args) async {
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channelName,
          codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
  }

  test('canInstall reflects the native grant', () async {
    mockChannel(canInstall: true);
    expect(await service.canInstall(), isTrue);

    service.dispose();
    service = ApkInstallService();
    mockChannel(canInstall: false);
    expect(await service.canInstall(), isFalse);
  });

  test('canInstall → false when the channel is unavailable', () async {
    // No mock handler: the invoke throws MissingPluginException.
    expect(await service.canInstall(), isFalse);
  });

  test('startInstall passes args and emits InstallStarted', () async {
    mockChannel();
    final events = <InstallEvent>[];
    final sub = service.events.listen(events.add);

    await service.startInstall(
      apkPath: '/data/app/AgentA-1.4.0.apk',
      sizeBytes: 123,
    );

    await Future<void>.delayed(Duration.zero);
    expect(recorded['apkPath'], '/data/app/AgentA-1.4.0.apk');
    expect(recorded['sizeBytes'], 123);
    expect(events, hasLength(1));
    expect(events.single, isA<InstallStarted>());
    await sub.cancel();
  });

  test('native install status: installed → InstallCompleted', () async {
    final events = <InstallEvent>[];
    final sub = service.events.listen(events.add);

    await nativeEvent('onInstallStatus', {'status': 'installed'});
    await Future<void>.delayed(Duration.zero);

    expect(events.single, isA<InstallCompleted>());
    await sub.cancel();
  });

  test(
    'native install status: failed(userCancelled) carried with detail',
    () async {
      final events = <InstallEvent>[];
      final sub = service.events.listen(events.add);

      await nativeEvent('onInstallStatus', {
        'status': 'failed',
        'reason': 'userCancelled',
        'detail': 'User rejected the install',
      });
      await Future<void>.delayed(Duration.zero);

      final event = events.single as InstallFailed;
      expect(event.reason, InstallFailureReason.userCancelled);
      expect(event.detail, 'User rejected the install');
      await sub.cancel();
    },
  );

  test('unknown native reason → unknown (never throws)', () async {
    final events = <InstallEvent>[];
    final sub = service.events.listen(events.add);

    await nativeEvent('onInstallStatus', {
      'status': 'failed',
      'reason': 'martianFailure',
    });
    await Future<void>.delayed(Duration.zero);

    expect(
      (events.single as InstallFailed).reason,
      InstallFailureReason.unknown,
    );
    await sub.cancel();
  });

  test('startInstall platform error → InstallFailed, classified', () async {
    mockChannel(startError: PlatformException(code: 'permissionDenied'));
    final events = <InstallEvent>[];
    final sub = service.events.listen(events.add);

    await service.startInstall(apkPath: '/x/y.apk');
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(
      (events.single as InstallFailed).reason,
      InstallFailureReason.permissionDenied,
    );
    await sub.cancel();
  });

  test(
    'openInstallPermissionSettings invokes the channel (best-effort)',
    () async {
      mockChannel();
      await service.openInstallPermissionSettings();
      expect(recorded['settingsOpened'], isTrue);
    },
  );
}
