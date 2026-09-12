// ignore_for_file: empty_catches
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import 'biometric_auth_service.dart';
import 'session_manager.dart';

class AppAuthCredential {
  final String uid;
  final String? email;
  final String? displayName;

  const AppAuthCredential({required this.uid, this.email, this.displayName});
}

class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;
  static GoTrueClient get _auth => _db.auth;

  static bool _backendReady = false;
  static bool get isBackendReady => _backendReady;
  static void markBackendReady() => _backendReady = true;

  static User? get currentUser {
    if (!_backendReady) return null;
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges {
    if (!_backendReady) return const Stream.empty();
    try {
      return _auth.onAuthStateChange;
    } catch (_) {
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
    final res = await _auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = res.user;
    if (user == null) throw Exception('Login failed: user is null');
    return _toCredential(user);
  }

  static Future<AppAuthCredential> register(
      String email, String password, String name) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': name},
    );
    final user = res.user;
    if (user == null) throw Exception('Registration failed: user is null');
    return _toCredential(user);
  }

  static bool _googleInitialized = false;

  static Future<void> ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final serverId = AppConfig.googleServerClientId;
    final webId = serverId.isEmpty ? null : serverId;
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? webId : null,
      serverClientId: webId,
    );
    _googleInitialized = true;
  }

  static Future<AppAuthCredential> signInWithGoogle() async {
    await ensureGoogleInitialized();
    if (AppConfig.googleServerClientId.isEmpty) {
      throw Exception(
          'Google sign-in not configured: GOOGLE_SERVER_CLIENT_ID missing from .env');
    }
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      final detail = e.description ?? e.code.name;
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('Google sign-in canceled ($detail). '
            'If you did not cancel, this usually means SHA-1 / OAuth client or Supabase Google provider misconfiguration.');
      }
      throw Exception('Google sign-in failed ($detail)');
    }
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google sign-in failed: no ID token');
    }
    String? accessToken;
    try {
      final authz =
          await account.authorizationClient.authorizationForScopes(['email', 'profile']);
      accessToken = authz?.accessToken;
    } catch (_) {}
    try {
      accessToken ??= (await account.authorizationClient.authorizeScopes(['email', 'profile']))
          .accessToken;
    } catch (_) {}
    final res = await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    final user = res.user;
    if (user == null) throw Exception('Google sign-in failed: user is null');
    return _toCredential(user);
  }

  static Future<void> logout() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await BiometricAuthService.disable();
    await SessionManager.clear();
    await _auth.signOut();
  }

  static Future<void> signOutOnly() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  static Future<void> updatePassword(String newPassword) async {
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> updateDisplayName(String displayName) async {
    await _auth.updateUser(
      UserAttributes(data: {'display_name': displayName}),
    );
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.resetPasswordForEmail(email.trim());
  }

  static Future<AppAuthCredential> reauthenticate(
      String email, String password) async {
    return login(email, password);
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!value.contains('@')) return 'Enter a valid email';
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'At least 6 characters';
    return null;
  }
}
