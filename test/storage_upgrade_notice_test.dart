import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/core/config/app_config.dart';

void main() {
  // The notice flag is process-global static state; reset it before each
  // case via the one-shot consume so tests stay order-independent.
  setUp(AppConfig.consumeStorageUpgradeNotice);

  group('AppConfig storage-upgrade notice (F11 part 4)', () {
    test('defaults to no notice (no false alarm)', () {
      expect(AppConfig.consumeStorageUpgradeNotice(), isFalse);
      expect(AppConfig.consumeStorageUpgradeNotice(), isFalse);
    });

    test('record is idempotent; consume is one-shot', () {
      AppConfig.recordStorageUpgradeLoss(
        state: 'legacyDataUnreadable',
        reason: 'missingAlgorithmMarkers',
        entryCount: 5,
        details: 'v9 data without algorithm markers',
      );
      // A retried boot may record again (e.g. backend retry re-runs init);
      // the notice must still fire exactly once.
      AppConfig.recordStorageUpgradeLoss(
        state: 'legacyDataDiscarded',
        reason: 'removedCipher',
        entryCount: 0,
        details: null,
      );
      expect(AppConfig.consumeStorageUpgradeNotice(), isTrue);
      expect(AppConfig.consumeStorageUpgradeNotice(), isFalse);
    });

    test('host test platform is not Android (hook no-op premise)', () {
      // The boot hook (lib/main.dart) early-returns on non-Android before
      // ever touching the plugin channel — the premise that keeps this
      // suite independent of a platform implementation.
      expect(Platform.isAndroid, isFalse);
    });
  });
}
