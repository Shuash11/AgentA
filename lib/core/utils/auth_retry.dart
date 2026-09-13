import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized retryability check for auth/network errors.
///
/// Uses typed exceptions instead of substring matching:
/// - [SocketException] -> retryable
/// - [TimeoutException] -> retryable
/// - [AuthException] with statusCode 408/429/5xx -> retryable
/// - [HttpException] (rare) -> retryable
/// Everything else -> not retryable.
///
/// Optionally caller can combine with [ConnectivityService.isOnline] for
/// additional signal, but this utility alone is substring-free.
class AuthRetryPolicy {
  const AuthRetryPolicy._();

  static bool isRetryable(Object error) {
    if (error is SocketException) {
      if (kDebugMode) debugPrint('[AuthRetry] SocketException => retryable: $error');
      return true;
    }
    if (error is TimeoutException) {
      if (kDebugMode) debugPrint('[AuthRetry] TimeoutException => retryable');
      return true;
    }
    if (error is HttpException) {
      if (kDebugMode) debugPrint('[AuthRetry] HttpException => retryable: $error');
      return true;
    }
    if (error is AuthException) {
      final code = error.statusCode;
      final isRetryableCode = _isRetryableStatusCode(code);
      if (kDebugMode) {
        debugPrint(
            '[AuthRetry] AuthException statusCode=$code message=${error.message} => retryable=$isRetryableCode');
      }
      return isRetryableCode;
    }
    // Supabase PostgrestException also has similar shape but auth path is main.
    // Fallback: check if error has statusCode property via dynamic? Avoid substring.
    try {
      final dynamic d = error;
      final sc = d.statusCode as String?;
      if (sc != null && _isRetryableStatusCode(sc)) {
        if (kDebugMode) debugPrint('[AuthRetry] dynamic statusCode=$sc => retryable');
        return true;
      }
    } catch (e) {
      // L20: the probe throws for error types without a statusCode getter —
      // expected, but log it so nothing is silently swallowed.
      if (kDebugMode) {
        debugPrint('[AuthRetry] statusCode probe failed for ${error.runtimeType}: $e');
      }
    }
    if (kDebugMode) debugPrint('[AuthRetry] ${error.runtimeType} => not retryable');
    return false;
  }

  static bool _isRetryableStatusCode(String? code) {
    if (code == null || code.isEmpty) return false;
    // 408 timeout, 429 rate-limit, 500-599 server
    if (code == '408' || code == '429') return true;
    final n = int.tryParse(code);
    if (n != null && n >= 500 && n <= 599) return true;
    return false;
  }
}
