import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/auth_retry.dart';
import 'biometric_auth_service.dart';
import 'session_manager.dart';

class AppAuthCredential {
  final String uid;
  final String? email;
  final String? displayName;

  const AppAuthCredential({required this.uid, this.email, this.displayName});
}

/// Typed failure for Google sign-in — replaces generic Exception(string).
/// Preserves original code + description, adds actionable hint.
class GoogleSignInFailure implements Exception {
  final String code;
  final String? detail;
  final String hint;

  const GoogleSignInFailure({
    required this.code,
    this.detail,
    required this.hint,
  });

  @override
  String toString() {
    final d = detail == null || detail!.isEmpty ? code : detail!;
    return 'GoogleSignInFailure($code): $d | Hint: $hint';
  }
}

class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;
  static GoTrueClient get _auth => _db.auth;

  static bool _backendReady = false;
  static bool get isBackendReady => _backendReady;
  static void markBackendReady() => _backendReady = true;

  /// Centralized retry check — delegates to AuthRetryPolicy (H10).
  static bool isRetryable(Object e) => AuthRetryPolicy.isRetryable(e);

  static void _guardBackendReady(String caller) {
    if (!_backendReady) {
      _log('[AuthService] $caller blocked — backend not ready');
      throw StateError('Backend not ready: $caller');
    }
    try {
      Supabase.instance.client;
    } catch (e) {
      _log('[AuthService] $caller blocked — client unavailable: $e');
      throw StateError('Supabase client unavailable: $caller');
    }
  }

  static User? get currentUser {
    if (!_backendReady) return null;
    try {
      return _auth.currentUser;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] currentUser read failed: $e');
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges {
    if (!_backendReady) return const Stream.empty();
    try {
      return _auth.onAuthStateChange;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthService] authStateChanges failed: $e');
      }
      return const Stream.empty();
    }
  }

  static AppAuthCredential _toCredential(User user) {
    final meta = user.userMetadata;
    final metaName = meta == null
        ? null
        : (meta['display_name'] ?? meta['full_name'] ?? meta['name'])
            as String?;
    return AppAuthCredential(
      uid: user.id,
      email: user.email,
      displayName: metaName,
    );
  }

  static Future<AppAuthCredential> login(String email, String password) async {
    _guardBackendReady('login');
    try {
      final res = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) throw Exception('Login failed: user is null');
      _log('[AuthService] login success uid=${user.id}');
      return _toCredential(user);
    } on StateError {
      rethrow;
    } catch (e, st) {
      _log('[AuthService] login failed: $e | $st | retryable=${isRetryable(e)}');
      rethrow;
    }
  }

  static Future<AppAuthCredential> register(
      String email, String password, String name) async {
    _guardBackendReady('register');
    try {
      final res = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': name},
      );
      final user = res.user;
      if (user == null) throw Exception('Registration failed: user is null');
      _log('[AuthService] register success uid=${user.id}');
      return _toCredential(user);
    } on StateError {
      rethrow;
    } catch (e, st) {
      _log('[AuthService] register failed: $e | $st | retryable=${isRetryable(e)}');
      rethrow;
    }
  }

  // ── Google Sign-In: modular, logged, typed failures ───────────────

  static bool _googleInitialized = false;
  static bool get isGoogleInitialized => _googleInitialized;

  static String _idSuffix(String id) {
    if (id.isEmpty) return '(empty)';
    if (id.length <= 8) return '***';
    return id.substring(id.length - 8);
  }

  static void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  /// Reset one-shot init so next sign-in re-validates & re-initializes.
  /// Called on logout and when env config changes (per reviewer finding #3).
  static void resetGoogleInit() {
    _googleInitialized = false;
    _log('[AuthService] resetGoogleInit() — will re-initialize on next sign-in');
  }

  static String? _validateGoogleId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      return 'Google sign-in not configured: GOOGLE_SERVER_CLIENT_ID missing or empty in .env. '
          'Add your Web Client ID from Google Cloud Console (Credentials > OAuth 2.0 Client IDs > Web application) — must end with .apps.googleusercontent.com';
    }
    if (!trimmed.endsWith('.apps.googleusercontent.com')) {
      return 'GOOGLE_SERVER_CLIENT_ID is malformed: must end with .apps.googleusercontent.com. '
          'Current suffix: ...${_idSuffix(trimmed)} — check you copied the Web Client ID, not Android Client ID';
    }
    return null;
  }

  static Future<void> ensureGoogleInitialized() async {
    if (_googleInitialized) {
      _log('[AuthService] ensureGoogleInitialized: already initialized, skipping');
      return;
    }
    // No backend guard here — Google init is independent, but log backend state.
    if (!_backendReady) {
      _log('[AuthService] ensureGoogleInitialized — backend not ready (proceeding, will guard at exchange)');
    }
    final serverId = AppConfig.googleServerClientId.trim();

    // MUST validate BEFORE initialize() — not after (reviewer #3).
    final validationError = _validateGoogleId(serverId);
    if (validationError != null) {
      _log(
          '[AuthService] ensureGoogleInitialized FAILED validation: $validationError | idSuffix: ${_idSuffix(serverId)}');
      throw GoogleSignInFailure(
        code: 'not_configured',
        detail: validationError,
        hint:
            'Add GOOGLE_SERVER_CLIENT_ID to .env (Web Client ID from Google Cloud Console). Must end with .apps.googleusercontent.com',
      );
    }

    final webId = serverId.isEmpty ? null : serverId;
    _log(
        '[AuthService] ensureGoogleInitialized: initializing | serverClientId suffix: ...${_idSuffix(serverId)} | kIsWeb:$kIsWeb');

    try {
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? webId : null,
        serverClientId: webId,
      );
      _googleInitialized = true;
      _log(
          '[AuthService] GoogleSignIn initialized successfully | suffix: ...${_idSuffix(serverId)}');
    } catch (e, stack) {
      _log(
          '[AuthService] GoogleSignIn.initialize failed: $e | suffix: ...${_idSuffix(serverId)} | stack: $stack');
      throw GoogleSignInFailure(
        code: 'init_failed',
        detail: e.toString(),
        hint:
            'GoogleSignIn initialization failed. Check GOOGLE_SERVER_CLIENT_ID and platform OAuth setup (SHA-1, bundle ID).',
      );
    }
  }

  /// Guards the one-shot recovery retry in [_authenticateWithGoogle].
  static bool _didRetryGoogleAuth = false;

  /// Google Play Services aborts the Credential Manager flow with a native
  /// "[16] Account reauth failed." cancellation when the cached Google
  /// authorization no longer matches this build's signing certificate (e.g.
  /// a differently-signed APK) or when the certificate is not registered for
  /// the app in Google Cloud Console.
  static bool _isReauthFailure(String detail) {
    final d = detail.toLowerCase();
    return d.contains('reauth failed') ||
        d.contains('reauth') ||
        d.contains('[16]') ||
        d.contains('account reauth');
  }

  static Future<GoogleSignInAccount> _authenticateWithGoogle() async {
    _log('[AuthService] authenticate() start');
    try {
      final account = await GoogleSignIn.instance.authenticate();
      _log('[AuthService] authenticate() success | idToken present: ${account.authentication.idToken != null}');
      return account;
    } on GoogleSignInException catch (e) {
      final codeName = e.code.name;
      final detail = e.description ?? codeName;
      _log('[AuthService] authenticate() GoogleSignInException: code=$codeName detail=$detail');

      final isReauth = e.code == GoogleSignInExceptionCode.canceled &&
          _isReauthFailure(detail);

      // Recovery: clear the cached Google credential state and retry once.
      // A stale authorization from an earlier (differently-signed) install
      // otherwise keeps failing this way even after configuration is fixed.
      if (isReauth && !_didRetryGoogleAuth) {
        _didRetryGoogleAuth = true;
        _log('[AuthService] reauth failure — clearing cached Google state and retrying once');
        try {
          await GoogleSignIn.instance.signOut();
        } catch (signOutError) {
          _log('[AuthService] signOut before retry failed (ignored): $signOutError');
        }
        try {
          return await _authenticateWithGoogle();
        } finally {
          _didRetryGoogleAuth = false;
        }
      }

      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleSignInFailure(
          code: isReauth ? 'reauth_failed' : codeName,
          detail: detail,
          hint: isReauth
              ? 'Google rejected the saved sign-in (native: $detail). This build\'s signing '
                  'certificate is not authorized for Google Sign-In, or the cached authorization '
                  'is stale. Fix: register the APK signing SHA-1 in Google Cloud Console as an '
                  'ANDROID OAuth client for package com.agenta.AgentA (each CI build prints the '
                  'exact fingerprint in its job summary; see docs/google-signin-setup.md), then '
                  'retry. Also confirm GOOGLE_SERVER_CLIENT_ID is the Web client ID from the same '
                  'project that Supabase Auth > Providers > Google uses.'
              : 'Google sign-in canceled ($detail). If you did not cancel, this usually means SHA-1 / OAuth client or Supabase Google provider misconfiguration. Verify SHA-1 in Firebase/Google Cloud Console and that Supabase Dashboard > Auth > Providers > Google is enabled with correct Web Client ID/Secret.',
        );
      }
      throw GoogleSignInFailure(
        code: codeName,
        detail: detail,
        hint:
            'Google sign-in failed ($detail). Check device connectivity and OAuth configuration.',
      );
    } catch (e, stack) {
      _log('[AuthService] authenticate() unexpected error: $e | stack: $stack');
      rethrow;
    }
  }

  static String _requireIdToken(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    final present = idToken != null && idToken.isNotEmpty;
    _log('[AuthService] idToken presence: $present (never logging token value)');
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleSignInFailure(
        code: 'no_id_token',
        detail: 'Google sign-in failed: no ID token returned',
        hint:
            'No ID token from Google. Check that GOOGLE_SERVER_CLIENT_ID is a Web Client ID and that the OAuth consent screen is configured.',
      );
    }
    return idToken;
  }

  static Future<String?> _fetchAccessToken(
      GoogleSignInAccount account) async {
    String? accessToken;
    try {
      final authz = await account.authorizationClient
          .authorizationForScopes(['email', 'profile']);
      accessToken = authz?.accessToken;
      _log(
          '[AuthService] authorizationForScopes result: ${accessToken != null ? "got token" : "no token (will try authorizeScopes)"}');
    } catch (e, stack) {
      _log(
          '[AuthService] authorizationForScopes failed (will try authorizeScopes): $e | stack: $stack');
    }

    if (accessToken == null) {
      try {
        final authz2 = await account.authorizationClient
            .authorizeScopes(['email', 'profile']);
        accessToken = authz2.accessToken;
        final got = accessToken.isNotEmpty;
        _log('[AuthService] authorizeScopes result: ${got ? "got token" : "still no token"}');
      } catch (e, stack) {
        _log('[AuthService] authorizeScopes failed: $e | stack: $stack');
      }
    }

    if (accessToken == null) {
      _log('[AuthService] accessToken unavailable — proceeding with idToken only');
    } else {
      _log('[AuthService] accessToken present: true (never logging token)');
    }
    return accessToken;
  }

  static Future<AuthResponse> _exchangeWithSupabase({
    required String idToken,
    String? accessToken,
  }) async {
    _log(
        '[AuthService] signInWithIdToken start | idToken present: true | accessToken present: ${accessToken != null}');
    try {
      final res = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      _log(
          '[AuthService] signInWithIdToken success | user: ${res.user?.id ?? "(null)"}');
      return res;
    } on AuthException catch (e) {
      _log('[AuthService] signInWithIdToken AuthException: ${e.message}');
      throw GoogleSignInFailure(
        code: 'supabase_rejected',
        detail: e.message,
        hint:
            'Supabase rejected Google token (check Dashboard Google provider + Web Client ID/Secret): ${e.message}',
      );
    } catch (e, stack) {
      _log(
          '[AuthService] signInWithIdToken unexpected error: $e | stack: $stack');
      rethrow;
    }
  }

  static Future<AppAuthCredential> signInWithGoogle() async {
    _guardBackendReady('signInWithGoogle');
    await ensureGoogleInitialized();

    final account = await _authenticateWithGoogle();
    final idToken = _requireIdToken(account);
    final accessToken = await _fetchAccessToken(account);
    final res = await _exchangeWithSupabase(
        idToken: idToken, accessToken: accessToken);

    final user = res.user;
    if (user == null) {
      _log('[AuthService] signInWithGoogle failed: Supabase user is null after exchange');
      throw const GoogleSignInFailure(
        code: 'no_user',
        detail: 'Google sign-in failed: Supabase user is null after token exchange',
        hint: 'Supabase did not return a user. Check Supabase logs and Google provider config.',
      );
    }
    _log('[AuthService] signInWithGoogle success | uid: ${user.id}');
    return _toCredential(user);
  }

  static Future<void> logout() async {
    // logout should work offline too — only guard Supabase signOut
    try {
      await GoogleSignIn.instance.signOut();
      _log('[AuthService] Google signOut success');
    } catch (e, stack) {
      _log('[AuthService] Google signOut failed (ignored): $e | stack: $stack');
    }
    resetGoogleInit();
    await BiometricAuthService.disable();
    await SessionManager.clear();
    if (_backendReady) {
      try {
        await _auth.signOut();
      } catch (e, st) {
        _log('[AuthService] Supabase signOut failed (offline?): $e | $st');
      }
    } else {
      _log('[AuthService] logout — backend not ready, skipped Supabase signOut');
    }
    _log('[AuthService] logout complete');
  }

  static Future<void> signOutOnly() async {
    try {
      await GoogleSignIn.instance.signOut();
      _log('[AuthService] Google signOutOnly success');
    } catch (e, stack) {
      _log(
          '[AuthService] Google signOutOnly failed (ignored): $e | stack: $stack');
    }
    resetGoogleInit();
    if (_backendReady) {
      try {
        await _auth.signOut();
      } catch (e, st) {
        _log('[AuthService] signOutOnly Supabase failed: $e | $st');
      }
    }
    _log('[AuthService] signOutOnly complete');
  }

  static Future<void> updatePassword(String newPassword) async {
    _guardBackendReady('updatePassword');
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> updateDisplayName(String displayName) async {
    _guardBackendReady('updateDisplayName');
    await _auth.updateUser(
      UserAttributes(data: {'display_name': displayName}),
    );
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    _guardBackendReady('sendPasswordResetEmail');
    // M14: deep-link redirect so the reset flow returns to the app.
    // Requires the com.agenta.agenta://reset intent-filter in
    // AndroidManifest.xml + Supabase Dashboard > Auth > URL Configuration
    // (Additional Redirect URLs must allow com.agenta.agenta://reset).
    await _auth.resetPasswordForEmail(
      email.trim(),
      // gotrue >=2.x names this `redirectTo` (older `emailRedirectTo`).
      redirectTo: 'com.agenta.agenta://reset',
    );
  }

  static Future<AppAuthCredential> reauthenticate(
      String email, String password) async {
    _guardBackendReady('reauthenticate');
    return login(email, password);
  }

  static final RegExp _emailPattern = RegExp(
    r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+$",
  );

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final normalized = normalizeEmail(value);
    if (normalized.length > 254 || !_emailPattern.hasMatch(normalized)) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'At least 8 characters';
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasDigit = RegExp(r'[0-9]').hasMatch(value);
    if (!hasLetter || !hasDigit) {
      return 'Use letters + numbers for a stronger password';
    }
    return null;
  }
}
