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
///
/// `detail` is display-bounded: dynamic sources (plugin internals, server
/// messages) are truncated via [truncateDetail] at the throw sites so the
/// in-app "Show details" toggle never renders unbounded text. The full raw
/// value stays in `kDebugMode` logs (see `_log` calls before each throw).
/// This object is in-memory only — never persisted (no DAO/session writes).
class GoogleSignInFailure implements Exception {
  final String code;
  final String? detail;
  final String hint;

  /// Max rendered detail length before an ellipsis suffix is appended.
  static const int maxDetailLength = 200;

  const GoogleSignInFailure({
    required this.code,
    this.detail,
    required this.hint,
  });

  /// Bounds a dynamic detail string for safe in-app display.
  /// Returns null for null/empty/whitespace-only input (so the login
  /// "Show details" toggle's `?? '(none)'` fallback renders); longer
  /// input is cut to [max] chars plus a '...' suffix.
  static String? truncateDetail(String? detail, [int max = maxDetailLength]) {
    if (detail == null) return null;
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max)}...';
  }

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
      _log(
        '[AuthService] login failed: $e | $st | retryable=${isRetryable(e)}',
      );
      rethrow;
    }
  }

  static Future<AppAuthCredential> register(
    String email,
    String password,
    String name,
  ) async {
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
      _log(
        '[AuthService] register failed: $e | $st | retryable=${isRetryable(e)}',
      );
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
    _log(
      '[AuthService] resetGoogleInit() — will re-initialize on next sign-in',
    );
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
      _log(
        '[AuthService] ensureGoogleInitialized: already initialized, skipping',
      );
      return;
    }
    // No backend guard here — Google init is independent, but log backend state.
    if (!_backendReady) {
      _log(
        '[AuthService] ensureGoogleInitialized — backend not ready (proceeding, will guard at exchange)',
      );
    }
    final serverId = AppConfig.googleServerClientId.trim();

    // MUST validate BEFORE initialize() — not after (reviewer #3).
    final validationError = _validateGoogleId(serverId);
    if (validationError != null) {
      _log(
        '[AuthService] ensureGoogleInitialized FAILED validation: $validationError | idSuffix: ${_idSuffix(serverId)}',
      );
      throw GoogleSignInFailure(
        code: 'not_configured',
        detail: GoogleSignInFailure.truncateDetail(validationError),
        hint:
            'Add GOOGLE_SERVER_CLIENT_ID to .env (Web Client ID from Google Cloud Console). Must end with .apps.googleusercontent.com',
      );
    }

    final webId = serverId.isEmpty ? null : serverId;
    _log(
      '[AuthService] ensureGoogleInitialized: initializing | serverClientId suffix: ...${_idSuffix(serverId)} | kIsWeb:$kIsWeb',
    );

    try {
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? webId : null,
        serverClientId: webId,
      );
      _googleInitialized = true;
      _log(
        '[AuthService] GoogleSignIn initialized successfully | suffix: ...${_idSuffix(serverId)}',
      );
    } catch (e, stack) {
      _log(
        '[AuthService] GoogleSignIn.initialize failed: $e | suffix: ...${_idSuffix(serverId)} | stack: $stack',
      );
      throw GoogleSignInFailure(
        code: 'init_failed',
        detail: GoogleSignInFailure.truncateDetail(e.toString()),
        hint:
            'GoogleSignIn initialization failed. Check GOOGLE_SERVER_CLIENT_ID and platform OAuth setup (SHA-1, bundle ID).',
      );
    }
  }

  /// Guards recovery behavior in [_authenticateWithGoogle].
  ///
  /// The [16] "Account reauth failed." native cancellation is surfaced
  /// immediately (no auto-retry double account picker); the stale cached
  /// credential is cleared via signOut() so the next manual attempt starts
  /// clean.

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
      _log(
        '[AuthService] authenticate() success | idToken present: ${account.authentication.idToken != null}',
      );
      return account;
    } on GoogleSignInException catch (e) {
      final codeName = e.code.name;
      final detail = e.description ?? codeName;
      _log(
        '[AuthService] authenticate() GoogleSignInException: code=$codeName detail=$detail',
      );

      final isReauth =
          e.code == GoogleSignInExceptionCode.canceled &&
          _isReauthFailure(detail);

      // Recovery: clear the cached Google credential state so the NEXT manual
      // attempt starts clean. We deliberately do NOT auto-retry here: the
      // [16] reauth failure happens AFTER the user picks an account, so an
      // automatic retry would re-open the account picker (double prompt).
      // Manual retry after this signOut() is the documented workaround for
      // stale cached authorizations.
      if (isReauth) {
        _log(
          '[AuthService] reauth failure — clearing cached Google state for next manual attempt',
        );
        try {
          await GoogleSignIn.instance.signOut();
        } catch (signOutError) {
          _log(
            '[AuthService] signOut after reauth failure failed (ignored): $signOutError',
          );
        }
      }

      // Bounded copy for display: the raw `detail` stays in the kDebugMode
      // log above; the typed failure (detail + hint interpolations) renders
      // in the in-app "Show details" toggle, so it must stay bounded.
      final displayDetail =
          GoogleSignInFailure.truncateDetail(detail) ?? codeName;

      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleSignInFailure(
          code: isReauth ? 'reauth_failed' : codeName,
          detail: displayDetail,
          hint: isReauth
              ? 'Google rejected the saved sign-in (native: $displayDetail). This build\'s signing '
                    'certificate is not authorized for Google Sign-In, or the cached authorization '
                    'is stale. Fix: register the APK signing SHA-1 in Google Cloud Console as an '
                    'ANDROID OAuth client for package com.agenta.AgentA (each CI build prints the '
                    'exact fingerprint in its job summary; see docs/google-signin-setup.md), then '
                    'retry. Also confirm GOOGLE_SERVER_CLIENT_ID is the Web client ID from the same '
                    'project that Supabase Auth > Providers > Google uses.'
              : 'Google sign-in canceled ($displayDetail). If you did not cancel, this usually means SHA-1 / OAuth client or Supabase Google provider misconfiguration. Verify SHA-1 in Firebase/Google Cloud Console and that Supabase Dashboard > Auth > Providers > Google is enabled with correct Web Client ID/Secret.',
        );
      }
      throw GoogleSignInFailure(
        code: codeName,
        detail: displayDetail,
        hint:
            'Google sign-in failed ($displayDetail). Check device connectivity and OAuth configuration.',
      );
    } catch (e, stack) {
      _log('[AuthService] authenticate() unexpected error: $e | stack: $stack');
      rethrow;
    }
  }

  static String _requireIdToken(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    final present = idToken != null && idToken.isNotEmpty;
    _log(
      '[AuthService] idToken presence: $present (never logging token value)',
    );
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

  static Future<String?> _fetchAccessToken(GoogleSignInAccount account) async {
    String? accessToken;
    try {
      final authz = await account.authorizationClient.authorizationForScopes([
        'email',
        'profile',
      ]);
      accessToken = authz?.accessToken;
      _log(
        '[AuthService] authorizationForScopes result: ${accessToken != null ? "got token" : "no token (will try authorizeScopes)"}',
      );
    } catch (e, stack) {
      _log(
        '[AuthService] authorizationForScopes failed (will try authorizeScopes): $e | stack: $stack',
      );
    }

    if (accessToken == null) {
      try {
        final authz2 = await account.authorizationClient.authorizeScopes([
          'email',
          'profile',
        ]);
        accessToken = authz2.accessToken;
        final got = accessToken.isNotEmpty;
        _log(
          '[AuthService] authorizeScopes result: ${got ? "got token" : "still no token"}',
        );
      } catch (e, stack) {
        _log('[AuthService] authorizeScopes failed: $e | stack: $stack');
      }
    }

    if (accessToken == null) {
      _log(
        '[AuthService] accessToken unavailable — proceeding with idToken only',
      );
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
      '[AuthService] signInWithIdToken start | idToken present: true | accessToken present: ${accessToken != null}',
    );
    try {
      final res = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      _log(
        '[AuthService] signInWithIdToken success | user: ${res.user?.id ?? "(null)"}',
      );
      return res;
    } on AuthException catch (e) {
      _log('[AuthService] signInWithIdToken AuthException: ${e.message}');
      final displayMessage =
          GoogleSignInFailure.truncateDetail(e.message) ?? e.message;
      throw GoogleSignInFailure(
        code: 'supabase_rejected',
        detail: displayMessage,
        hint:
            'Supabase rejected Google token (check Dashboard Google provider + Web Client ID/Secret): $displayMessage',
      );
    } catch (e, stack) {
      _log(
        '[AuthService] signInWithIdToken unexpected error: $e | stack: $stack',
      );
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
      idToken: idToken,
      accessToken: accessToken,
    );

    final user = res.user;
    if (user == null) {
      _log(
        '[AuthService] signInWithGoogle failed: Supabase user is null after exchange',
      );
      throw const GoogleSignInFailure(
        code: 'no_user',
        detail:
            'Google sign-in failed: Supabase user is null after token exchange',
        hint:
            'Supabase did not return a user. Check Supabase logs and Google provider config.',
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
      _log(
        '[AuthService] logout — backend not ready, skipped Supabase signOut',
      );
    }
    _log('[AuthService] logout complete');
  }

  static Future<void> signOutOnly() async {
    try {
      await GoogleSignIn.instance.signOut();
      _log('[AuthService] Google signOutOnly success');
    } catch (e, stack) {
      _log(
        '[AuthService] Google signOutOnly failed (ignored): $e | stack: $stack',
      );
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
    await _auth.updateUser(UserAttributes(data: {'display_name': displayName}));
  }

  // ── Password reset via Gmail email OTP ─────────────────────────────
  //
  // TODO(Supabase Dashboard config): OTP delivery, expiry, and rate limits
  // live in the Supabase Dashboard and cannot be changed from code — the
  // built-in/default email provider must send the OTP (Auth > Providers >
  // Email), and redirect/OTP settings are configured under
  // Dashboard > Authentication > URL Configuration.
  //
  // Sends a 6-digit OTP to the user's Gmail inbox (does not create a user).
  // The user completes the reset in-app via [resetPasswordWithOtp].
  static Future<void> sendOtpForReset(String email) async {
    _guardBackendReady('sendOtpForReset');
    await _auth.signInWithOtp(email: email.trim(), shouldCreateUser: false);
  }

  /// Verifies the emailed OTP, signs the user in, and sets the new password.
  ///
  /// gotrue 2.27.2's [GoTrueClient.verifyOTP] has no `password` parameter, so
  /// the OTP first establishes the session (email type returns a session for
  /// the matching user) and the new password is then set via [updatePassword].
  static Future<void> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    _guardBackendReady('resetPasswordWithOtp');
    final res = await _auth.verifyOTP(
      type: OtpType.email,
      email: email.trim(),
      token: otp.trim(),
    );
    if (res.user == null) {
      throw const AuthException('OTP verification failed: user is null');
    }
    await updatePassword(newPassword);
  }

  static Future<AppAuthCredential> reauthenticate(
    String email,
    String password,
  ) async {
    _guardBackendReady('reauthenticate');
    return login(email, password);
  }

  // ── Second-factor layer for password change (cycle-31 · phase P2) ─────
  //
  // Service-layer building blocks for the account-class matrix in
  // plans/cycle-31-second-factor-password-change.md. No UI here: phase P3
  // wires these into the change-password flow.

  /// Provider id of a Google-linked Supabase identity.
  static const String _googleProvider = 'google';

  /// True when [user] is linked to a Google account.
  ///
  /// Detection rule (P1-verified, binding):
  ///  * primary — [User.identities] holds an identity whose provider is
  ///    `google`;
  ///  * secondary — [User.appMetadata]['provider'] is `google`.
  ///
  /// Known failure mode (documented, not hidden): when an account that was
  /// registered with email/password later signs in with Google, Supabase can
  /// create a SECOND user instead of linking the identities. Such a session
  /// carries no Google identity and classifies as email/password here, which
  /// selects the STRONGER factor set (current password + device credential).
  /// The failure direction is safe; it is still reported, not hidden.
  static bool isGoogleLinked(User user) {
    final identities = user.identities;
    if (identities != null) {
      for (final identity in identities) {
        if (identity.provider == _googleProvider) return true;
      }
    }
    return user.appMetadata['provider'] == _googleProvider;
  }

  /// Test seam for [verifyGoogleReauth].
  ///
  /// When set, the email of the account that confirmed the device comes from
  /// this callback instead of the google_sign_in plugin. The plugin's account
  /// type has a private constructor, so the plugin call itself cannot be
  /// faked without adding a dev dependency. Production leaves this null.
  @visibleForTesting
  static set googleAccountEmailForTest(Future<String?> Function()? value) {
    _googleAccountEmailForTest = value;
  }

  static Future<String?> Function()? _googleAccountEmailForTest;

  /// Verifies that the Google account confirming this device is the account
  /// that owns the current session — the Google factor of the cycle-31
  /// account-class matrix.
  ///
  /// Returns the authenticated [GoogleSignInAccount] on success. Every other
  /// outcome is a typed [GoogleSignInFailure] the caller can map to a
  /// fallback trigger:
  ///  * `canceled` — the user dismissed the account chooser;
  ///  * `unknownError` (this also covers "no credential returned"),
  ///    `interrupted`, `clientConfigurationError`,
  ///    `providerConfigurationError`, `uiUnavailable` — the platform refused
  ///    the request;
  ///  * `unsupported` — the platform cannot show the interactive prompt;
  ///  * `not_configured` / `init_failed` — the Google client is unusable;
  ///  * `email_mismatch` — the confirmed account is not the session account.
  ///
  /// google_sign_in 7.x throws for every non-success outcome ("or throws a
  /// GoogleSignInException for any other outcome"), so a canceled or silent
  /// result can never be read as a satisfied factor.
  ///
  /// The production path never returns null: success returns the account and
  /// every failure throws. The nullable type belongs to the P1-fixed
  /// signature; the only null comes from the test seam, which has no plugin
  /// account object to hand back.
  static Future<GoogleSignInAccount?> verifyGoogleReauth(
    String expectedEmail,
  ) async {
    final injectedEmail = _googleAccountEmailForTest;
    if (injectedEmail != null) {
      final email = await injectedEmail();
      if (email == null) return null;
      _assertGoogleAccountEmail(email, expectedEmail);
      return null;
    }

    final GoogleSignInAccount account;
    try {
      await ensureGoogleInitialized();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const GoogleSignInFailure(
          code: 'unsupported',
          detail: 'Google cannot show the verify-it\'s-you prompt here',
          hint:
              'Google re-authentication is unavailable on this platform. Use the emailed OTP step-up instead.',
        );
      }
      account = await _authenticateWithGoogle();
    } on GoogleSignInFailure {
      rethrow;
    } on UnsupportedError catch (e) {
      _log('[AuthService] verifyGoogleReauth unsupported: $e');
      throw const GoogleSignInFailure(
        code: 'unsupported',
        detail: 'Google re-authentication is not supported on this platform',
        hint:
            'Google re-authentication is unavailable on this platform. Use the emailed OTP step-up instead.',
      );
    } catch (e, stack) {
      _log('[AuthService] verifyGoogleReauth failed: $e | $stack');
      throw GoogleSignInFailure(
        code: 'unknownError',
        detail: GoogleSignInFailure.truncateDetail(e.toString()),
        hint:
            'Google re-authentication failed. Use the emailed OTP step-up instead.',
      );
    }

    _assertGoogleAccountEmail(account.email, expectedEmail);
    return account;
  }

  /// Throws a typed failure when the confirmed Google account is not the
  /// account that owns the current session.
  ///
  /// Email values are never logged (identity data) — only the outcome.
  static void _assertGoogleAccountEmail(
    String accountEmail,
    String expectedEmail,
  ) {
    final actual = accountEmail.trim().toLowerCase();
    final expected = expectedEmail.trim().toLowerCase();
    if (actual.isEmpty || actual != expected) {
      _log(
        '[AuthService] verifyGoogleReauth rejected: the confirmed Google '
        'account is not the signed-in account',
      );
      throw const GoogleSignInFailure(
        code: 'email_mismatch',
        detail:
            'Google re-authentication confirmed a different account than the signed-in one',
        hint:
            'The Google account that confirmed this device does not match the account you are signed in to. Sign in with the matching Google account, or use the emailed OTP step-up.',
      );
    }
  }

  // ── Email-OTP step-up (the fallback factor) ──────────────────────────

  /// Sends a one-time code to [email] for the password-change step-up.
  ///
  /// Fallback factor of the cycle-31 matrix: used when the Google factor is
  /// unavailable (plugin failure, unsupported platform, or an account-email
  /// mismatch). [shouldCreateUser] must stay `false` — a step-up code must
  /// never create an account (same rule as [sendOtpForReset]).
  ///
  /// The code is delivered to the inbox and verified by [verifyOtpStepUp]; it
  /// never passes through the app's logs.
  static Future<void> sendOtpForStepUp(
    String email, {
    bool shouldCreateUser = false,
  }) async {
    _guardBackendReady('sendOtpForStepUp');
    await _auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: shouldCreateUser,
    );
  }

  /// Verifies the emailed step-up code for [email].
  ///
  /// Returns true when Supabase accepted the code (a session was returned for
  /// the account); a rejected or expired code returns false so the caller
  /// aborts the password change. The code value is never logged — only the
  /// Supabase error code.
  ///
  /// Note: `verifyOTP` with [OtpType.email] also signs the account in. The
  /// user already holds a session in this flow; phase P3 decides whether the
  /// refreshed session is kept (plan cycle-31, phase P3).
  static Future<bool> verifyOtpStepUp(String email, String token) async {
    _guardBackendReady('verifyOtpStepUp');
    if (token.trim().isEmpty) {
      _log('[AuthService] verifyOtpStepUp rejected: empty code');
      return false;
    }
    try {
      final res = await _auth.verifyOTP(
        type: OtpType.email,
        email: email.trim(),
        token: token.trim(),
      );
      if (res.user == null) {
        _log('[AuthService] verifyOtpStepUp failed: no user returned');
        return false;
      }
      return true;
    } on AuthException catch (e) {
      // Log the error CODE only — never the message (it can echo the input)
      // and never the code itself.
      _log('[AuthService] verifyOtpStepUp rejected: code=${e.code}');
      return false;
    }
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
