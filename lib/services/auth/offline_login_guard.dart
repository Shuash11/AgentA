import 'package:flutter/foundation.dart';

/// C3: offline-login safety gate for password-provider rows.
///
/// Never grants a session without proof (salted-hash verification happens in
/// the caller). This guard adds:
/// - per-email failure counting with a lockout window (rate-limit),
/// - credential wipe trigger after [maxFailuresBeforeWipe] failures,
/// - a regression-test hook ([resetForTest], [failureCountForTest]).
class OfflineLoginGuard {
  static const int maxAttempts = 5;
  static const Duration lockoutWindow = Duration(minutes: 5);
  static const int maxFailuresBeforeWipe = 10;

  static final Map<String, List<DateTime>> _failures = {};
  static final Map<String, DateTime> _lockedUntil = {};

  @visibleForTesting
  static void resetForTest() {
    _failures.clear();
    _lockedUntil.clear();
  }

  @visibleForTesting
  static int failureCountForTest(String email) {
    return _failures[_key(email)]?.length ?? 0;
  }

  static String _key(String email) => email.trim().toLowerCase();

  /// True when this email is currently locked out (rate-limit hit).
  static bool isLockedOut(String email) {
    final until = _lockedUntil[_key(email)];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _lockedUntil.remove(_key(email));
      return false;
    }
    return true;
  }

  /// Record a failed offline attempt. Returns true when the caller should
  /// wipe the local credential (too many failures — possible brute force).
  static bool recordFailure(String email) {
    final key = _key(email);
    final now = DateTime.now();
    final list = (_failures[key] ?? <DateTime>[])
      ..removeWhere((t) => now.difference(t) > lockoutWindow)
      ..add(now);
    _failures[key] = list;
    if (kDebugMode) {
      debugPrint('[OfflineLoginGuard] failure $key count=${list.length}');
    }
    if (list.length >= maxAttempts) {
      _lockedUntil[key] = now.add(lockoutWindow);
    }
    return list.length >= maxFailuresBeforeWipe;
  }

  static void clearFailures(String email) {
    _failures.remove(_key(email));
    _lockedUntil.remove(_key(email));
  }
}
