import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/connectivity_service.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/biometric_auth_service.dart';
import '../../services/auth/offline_login_guard.dart';
import '../../services/auth/password_hasher.dart';
import '../../services/auth/session_manager.dart';
import '../../repositories/user_repository.dart';
import '../../data/local/local_user_dao.dart';
import '../../data/local/local_chat_dao.dart';
import '../../data/local/local_message_dao.dart';
import '../shared/app_shell.dart';
import '../shared/system_keyboard_text_field.dart';
import 'register.dart';
import 'forgot_password.dart';

/// Result of attempting to claim an offline-created account (Bug 4).
class _OfflineClaimResult {
  /// Credential from the successful online re-register
  /// (null when the claim completed as a plain offline sign-in).
  final AppAuthCredential? credential;

  /// True when the claim finished as a plain offline sign-in — the session
  /// was already saved inside the claim and the caller must route offline.
  final bool offlineSignedIn;

  const _OfflineClaimResult({this.credential, this.offlineSignedIn = false});
}

/// User-facing result of mapping a Google sign-in error.
class _GoogleSignInPresentation {
  final String message;
  final GoogleSignInFailure? failure;
  final bool isCancel;

  const _GoogleSignInPresentation({
    required this.message,
    this.failure,
    this.isCancel = false,
  });
}

/// Single label/value line inside the diagnostics dialog.
class _DiagnosticsRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagnosticsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTypography.label.copyWith(color: colors.subtext),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: AppTypography.body.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking warning shown at the top of login when
/// [AppConfig.googleConfigured] is false. Never blocks sign-in.
class _GoogleConfigBanner extends StatelessWidget {
  final ThemeColors colors;
  final String message;

  const _GoogleConfigBanner({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.base,
        borderRadius: AppRadius.bannerRadius,
        boxShadow: AppShadows.raised,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warningText,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google sign-in needs setup',
                  style: AppTypography.label.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '$message Check the setup docs for SHA-1 / OAuth / Supabase steps.',
                  style: AppTypography.labelSm.copyWith(color: colors.subtext),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot safety notice shown on login when the boot-time secure-storage
/// upgrade check reported data loss (F11 part 4). Static friendly text only
/// — raw plugin detail stays in the boot-time debug log
/// (docs/error-hygiene.md).
class _StorageUpgradeNotice extends StatelessWidget {
  final ThemeColors colors;

  const _StorageUpgradeNotice({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.base,
        borderRadius: AppRadius.bannerRadius,
        boxShadow: AppShadows.raised,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.lock_reset_rounded,
              color: AppColors.warningText,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'You were signed out after the app updated. Please sign in '
              'again.',
              style: AppTypography.label.copyWith(color: colors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _biometricReady = false;
  String? _errorMessage;

  // F11 part 4: one-shot upgrade-loss notice consumed from [AppConfig].
  bool _showStorageNotice = false;

  // Google sign-in UX state: distinguishes genuine user-cancel from
  // repeated cancel (almost certainly a setup issue).
  int _consecutiveGoogleCancel = 0;
  GoogleSignInFailure? _lastGoogleFailure;
  bool _showGoogleFailureDetails = false;

  /// Android applicationId (must match SHA-1 registration in
  /// Google Cloud Console / Firebase). Kept as a constant so the
  /// diagnostics dialog never needs a new platform plugin.
  static const String _androidPackageName = 'com.agenta.AgentA';

  @override
  void initState() {
    super.initState();
    _showStorageNotice = AppConfig.consumeStorageUpgradeNotice();
    unawaited(_checkBiometric());
  }

  Future<void> _checkBiometric() async {
    final ready =
        await BiometricAuthService.isSupported() &&
        await BiometricAuthService.isEnrolled();
    final lastEmail = await SessionManager.lastEmail();
    if (mounted) {
      setState(() => _biometricReady = ready);
      if (lastEmail != null &&
          lastEmail.isNotEmpty &&
          _emailController.text.isEmpty) {
        _emailController.text = lastEmail;
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    // Normalize once so local lookups match regardless of typed casing
    // (Supabase lowercases addresses server-side anyway).
    final email = AuthService.normalizeEmail(_emailController.text);
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool isOnline = false;
    String? onlineUid;

    try {
      final cred = await AuthService.login(email, password);
      isOnline = true;
      onlineUid = cred.uid;

      if (cred.uid.isNotEmpty) {
        try {
          final existing = await UserRepository.getUserProfile(cred.uid);
          if (existing == null) {
            await UserRepository.createUserProfile(
              cred.uid,
              email,
              cred.displayName ?? 'User',
              '',
            );
          }
        } catch (e, stack) {
          if (kDebugMode) {
            debugPrint('[Login] _login ensure profile failed: $e | $stack');
          }
        }
        final dao = LocalUserDao();
        await dao.savePendingSignup(
          localId: cred.uid,
          email: email,
          password: PasswordHasher.hashPassword(password),
          displayName: cred.displayName ?? 'User',
          recoveryCode: '',
          isSynced: true,
          provider: 'password',
        );
        await SessionManager.saveSession(
          uid: cred.uid,
          email: email,
          provider: 'password',
        );
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[Login] _login online attempt failed: $e | $stack');
      }
      final isRetryable =
          !AuthService.isBackendReady || AuthService.isRetryable(e);
      if (isRetryable) {
        // Backend unreachable or transient network/server error - try offline login
        _errorMessage = null;
        isOnline = false;
        if (kDebugMode) {
          debugPrint('[Login] retryable error, falling back offline');
        }
      } else {
        // Auth error (wrong password, user not found, etc.).
        // Accounts first created offline have no Supabase user yet, so their
        // first online sign-in fails with invalid credentials. If the typed
        // password proves ownership of the local row, create the account
        // online now instead of dead-ending the user.
        final claimed = await _tryClaimOfflineAccount(email, password);
        if (claimed != null) {
          if (claimed.offlineSignedIn) {
            // Bug 4: plain offline sign-in completed inside the claim —
            // route offline instead of returning null → "Login failed".
            if (!mounted) return;
            setState(() => _isLoading = false);
            _goToDashboard(isOnline: false);
            return;
          }
          isOnline = true;
          onlineUid = claimed.credential?.uid;
          if (kDebugMode) {
            debugPrint(
              '[Login] offline account claimed online | uid=${claimed.credential?.uid}',
            );
          }
        } else {
          final errorString = e.toString().toLowerCase();
          if (mounted) {
            setState(() {
              _isLoading = false;
              String errorMsg = 'Login failed';
              if (errorString.contains('user-not-found') ||
                  errorString.contains('invalid-email') ||
                  errorString.contains('invalid login credentials')) {
                errorMsg = 'Invalid email or password';
              } else if (errorString.contains('wrong-password') ||
                  errorString.contains('invalid-credential')) {
                errorMsg = 'Invalid password';
              } else if (errorString.contains('too-many-requests') ||
                  errorString.contains('rate limit')) {
                errorMsg = 'Too many attempts. Try again later.';
              } else if (errorString.contains('email not confirmed')) {
                errorMsg = 'Please confirm your email first';
              }
              _errorMessage = errorMsg;
            });
          }
          return;
        }
      }
    }

    if (isOnline) {
      setState(() => _isLoading = false);
      if (onlineUid != null) {
        await _offerBiometricEnroll(onlineUid);
      }
      _goToDashboard(isOnline: true);
      return;
    }

    try {
      final dao = LocalUserDao();
      final localUser = await dao.getUserByEmail(email);

      if (localUser != null) {
        final provider = (localUser['provider'] as String?) ?? 'password';
        // C3: google-provider rows must NEVER unlock offline with a typed
        // password — there is no password proof for them. Force the online
        // Google flow (or the biometric unlock bound to this uid).
        if (provider == 'google') {
          if (kDebugMode) {
            debugPrint('[Login] offline denied for google-provider row');
          }
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage =
                'This account uses Google sign-in. Connect to the internet '
                'and use "Continue with Google" (or fingerprint unlock).';
          });
          return;
        }
        // C3: rate-limit offline password attempts. The lockout checked
        // below is the active control; the wipe branch further down is the
        // guard's intentionally-defensive backstop, unreachable through this
        // gated path (see OfflineLoginGuard).
        if (OfflineLoginGuard.isLockedOut(email)) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Too many attempts. Try again later.';
          });
          return;
        }
        final storedHash = localUser['password'] as String;
        final storedSalt = (localUser['password_salt'] as String?) ?? '';
        final verification = PasswordHasher.verifyPassword(
          password,
          storedHash: storedHash,
          storedSalt: storedSalt,
        );
        if (verification.matched) {
          OfflineLoginGuard.clearFailures(email);
          if (verification.needsUpgrade) {
            // Verify-then-upgrade: the user is already authenticated, so a
            // failed re-hash must never block the login (best-effort; the
            // legacy row stays verifiable and the upgrade retries next time).
            try {
              await dao.tryUpgradePasswordHash(
                localId: localUser['local_id'] as String,
                expectedHash: storedHash,
                newHash: PasswordHasher.hashPassword(password),
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[Login] upgrade skipped: $e');
              }
            }
          }
          await SessionManager.saveSession(
            uid: localUser['local_id'] as String,
            email: email,
            provider: 'password',
          );
          setState(() => _isLoading = false);
          _goToDashboard(isOnline: false);
          return;
        }
        // Defensive backstop only: the gate above locks out at 5, so the
        // count never reaches the wipe threshold through this path.
        final shouldWipe = OfflineLoginGuard.recordFailure(email);
        if (shouldWipe) {
          try {
            await dao.delete(localUser['local_id'] as String);
            await SessionManager.dropStashedPassword(
              localUser['local_id'] as String,
            );
          } catch (e, stack) {
            if (kDebugMode) {
              debugPrint('[Login] offline wipe failed: $e | $stack');
            }
          }
          OfflineLoginGuard.clearFailures(email);
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[Login] _login offline fallback failed: $e | $stack');
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = 'Invalid email or password';
    });
  }

  /// Claims an account that was first created offline (no Supabase user yet).
  ///
  /// Called after an online sign-in failed. Ownership is proven against the
  /// local salted hash — the same proof the offline sign-in path uses — and
  /// only then is the account registered online. Returns the result, or null
  /// when this is not an offline-created account or proof fails.
  Future<_OfflineClaimResult?> _tryClaimOfflineAccount(
    String email,
    String password,
  ) async {
    try {
      final dao = LocalUserDao();
      final localUser = await dao.getUserByEmail(email);
      if (localUser == null) return null;
      if (((localUser['provider'] as String?) ?? 'password') != 'password') {
        return null;
      }
      if (((localUser['is_synced'] as int?) ?? 0) == 1) return null;

      final storedHash = (localUser['password'] as String?) ?? '';
      final storedSalt = (localUser['password_salt'] as String?) ?? '';
      final verification = PasswordHasher.verifyPassword(
        password,
        storedHash: storedHash,
        storedSalt: storedSalt,
      );
      if (!verification.matched) {
        if (kDebugMode) {
          debugPrint('[Login] claim skipped — local proof failed');
        }
        return null;
      }

      final localId = localUser['local_id'] as String;
      // Cycle-37 P4 (defect D): the name comes from the account's own row,
      // re-read here — the e-mail lookup can hand back another row for the
      // same address, and the profile edit writes the fresh name into the
      // account row.
      final accountRow =
          await dao.getPendingSignupByLocalId(localId) ?? localUser;
      final displayName = ((accountRow['display_name'] as String?) ?? '')
          .trim();
      final name = displayName.isEmpty ? 'User' : displayName;
      final recoveryHash = (localUser['recovery_code'] as String?) ?? '';

      // Bug 4: check connectivity before the online re-register. When the
      // device is offline, skip the online attempt entirely and complete a
      // plain offline sign-in against the locally stored account.
      final deviceOnline = await ConnectivityService.instance.isOnline();
      if (!deviceOnline) {
        if (kDebugMode) {
          debugPrint(
            '[Login] offline — plain offline sign-in (no online re-register)',
          );
        }
        if (verification.needsUpgrade) {
          // Same verify-then-upgrade contract as the offline login path:
          // post-proof, best-effort, never blocks the sign-in.
          try {
            await dao.tryUpgradePasswordHash(
              localId: localId,
              expectedHash: storedHash,
              newHash: PasswordHasher.hashPassword(password),
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[Login] upgrade skipped: $e');
            }
          }
        }
        await SessionManager.saveSession(
          uid: localId,
          email: email,
          provider: 'password',
        );
        return const _OfflineClaimResult(offlineSignedIn: true);
      }

      final cred = await AuthService.register(email, password, name);
      if (cred.uid.isEmpty) return null;

      try {
        await UserRepository.createUserProfileWithRecoveryHash(
          cred.uid,
          email,
          name,
          recoveryHash,
        );
      } catch (e) {
        // Profile is best-effort; the account itself is created.
        if (kDebugMode) debugPrint('[Login] claim profile upsert failed: $e');
      }

      await dao.markAsSynced(localId, cred.uid);

      // Local chats/messages are keyed by user id — carry them to the real
      // uid so nothing becomes invisible after the claim.
      try {
        await LocalChatDao.instance.migrateUserId(localId, cred.uid);
        await LocalMessageDao.instance.migrateUserId(localId, cred.uid);
      } catch (e) {
        if (kDebugMode) debugPrint('[Login] claim local migrate failed: $e');
      }

      await dao.savePendingSignup(
        localId: cred.uid,
        email: email,
        password: PasswordHasher.hashPassword(password),
        displayName: name,
        recoveryCode: recoveryHash,
        isSynced: true,
        provider: 'password',
      );
      await SessionManager.saveSession(
        uid: cred.uid,
        email: email,
        provider: 'password',
      );
      return _OfflineClaimResult(credential: cred);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[Login] claim failed: $e | $stack');
      return null;
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cred = await AuthService.signInWithGoogle();
      if (cred.uid.isNotEmpty) {
        final dao = LocalUserDao();
        await dao.savePendingSignup(
          localId: cred.uid,
          email: cred.email ?? '',
          password: '',
          displayName: cred.displayName ?? 'User',
          recoveryCode: '',
          isSynced: true,
          provider: 'google',
        );
        await SessionManager.saveSession(
          uid: cred.uid,
          email: cred.email ?? '',
          provider: 'google',
        );
        try {
          final existing = await UserRepository.getUserProfile(cred.uid);
          if (existing == null) {
            await UserRepository.createUserProfile(
              cred.uid,
              cred.email ?? '',
              cred.displayName ?? 'User',
              '',
            );
          }
        } catch (e, stack) {
          if (kDebugMode) {
            debugPrint(
              '[Login] Google sign-in ensure profile failed: $e | $stack',
            );
          }
        }
        await _offerBiometricEnroll(cred.uid);
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _consecutiveGoogleCancel = 0;
          _lastGoogleFailure = null;
          _showGoogleFailureDetails = false;
        });
      }
      _goToDashboard(isOnline: true);
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[Login] Google sign-in failed: $e | $stack');
      }
      if (!mounted) return;
      final presentation = _mapGoogleError(e);
      setState(() {
        _isLoading = false;
        if (presentation.isCancel) {
          _consecutiveGoogleCancel += 1;
        } else {
          _consecutiveGoogleCancel = 0;
        }
        _lastGoogleFailure = presentation.failure;
        _showGoogleFailureDetails = false;
        _errorMessage = presentation.message;
      });
    }
  }

  /// Maps a sign-in error to user-facing copy.
  ///
  /// Prefers the typed [GoogleSignInFailure] contract
  /// (`code` / `detail` / `hint`) from [AuthService]; falls back to
  /// legacy string matching only for unknown exception shapes.
  /// `failure.code == 'canceled'` is the single source of truth for
  /// genuine user-cancel — no substring checks on the typed path.
  _GoogleSignInPresentation _mapGoogleError(Object e) {
    if (e is GoogleSignInFailure) {
      if (e.code == 'canceled') {
        if (_consecutiveGoogleCancel >= 1) {
          return _GoogleSignInPresentation(
            message:
                'Repeated cancel — almost certainly a setup issue (SHA-1 / OAuth / Supabase). '
                'If you kept cancelling by hand, just try again.',
            failure: e,
            isCancel: true,
          );
        }
        return _GoogleSignInPresentation(
          message: 'You cancelled — try again.',
          failure: e,
          isCancel: true,
        );
      }
      switch (e.code) {
        case 'reauth_failed':
          return _GoogleSignInPresentation(
            message:
                'Google rejected this build\'s sign-in — signing key not authorized. See details.',
            failure: e,
          );
        case 'not_configured':
        case 'init_failed':
        case 'no_id_token':
          return _GoogleSignInPresentation(
            message:
                'Google sign-in not configured. Check SHA-1 / OAuth setup.',
            failure: e,
          );
        case 'supabase_rejected':
        case 'no_user':
          return _GoogleSignInPresentation(
            message:
                'Google sign-in was rejected. Check the Supabase Google provider setup.',
            failure: e,
          );
        default:
          return _GoogleSignInPresentation(
            message: 'Google sign-in failed (${e.code}).',
            failure: e,
          );
      }
    }

    // Legacy fallback for non-typed exceptions (old plugin shapes).
    final msg = e.toString().toLowerCase();
    if (msg.contains('cancelled by user') ||
        msg.contains('canceled') ||
        msg.contains('code canceled')) {
      if (_consecutiveGoogleCancel >= 1) {
        return const _GoogleSignInPresentation(
          message:
              'Repeated cancel — almost certainly a setup issue (SHA-1 / OAuth / Supabase). '
              'If you kept cancelling by hand, just try again.',
          isCancel: true,
        );
      }
      return const _GoogleSignInPresentation(
        message: 'You cancelled — try again.',
        isCancel: true,
      );
    }
    if (msg.contains('clientconfiguration') ||
        msg.contains('providerconfiguration') ||
        msg.contains('no id token') ||
        msg.contains('not configured') ||
        msg.contains('serverclientid') ||
        msg.contains('sha-1') ||
        msg.contains('oauth')) {
      return const _GoogleSignInPresentation(
        message: 'Google sign-in not configured. Check SHA-1 / OAuth setup.',
      );
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return const _GoogleSignInPresentation(
        message: 'Google sign-in failed. Check your connection.',
      );
    }
    return const _GoogleSignInPresentation(
      message: 'Google sign-in failed. Please try again.',
    );
  }

  /// Hidden diagnostics: long-press on the Google button.
  /// Shows package name + client-ID suffix + backend flag.
  /// Never shows the full client ID or any token.
  Future<void> _showGoogleDiagnostics() async {
    if (kDebugMode) {
      debugPrint(
        '[Login] Google diagnostics opened | suffix: ...${AppConfig.googleIdSuffixForLog} '
        '| configured: ${AppConfig.googleConfigured} '
        '| backendReady: ${AuthService.isBackendReady}',
      );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google sign-in diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DiagnosticsRow(label: 'Package', value: _androidPackageName),
            _DiagnosticsRow(
              label: 'Client ID suffix',
              value: '...${AppConfig.googleIdSuffixForLog}',
            ),
            _DiagnosticsRow(
              label: 'Configured',
              value: AppConfig.googleConfigured ? 'yes' : 'no',
            ),
            _DiagnosticsRow(
              label: 'Backend ready',
              value: AuthService.isBackendReady ? 'yes' : 'no',
            ),
            if (AppConfig.googleConfigError != null) ...[
              const SizedBox(height: 8),
              Text(
                AppConfig.googleConfigError!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Full client ID and tokens are never shown here.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlockWithBiometrics() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = await BiometricAuthService.unlock();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (uid != null) {
      final dao = LocalUserDao();
      final row = await dao.getPendingSignupByLocalId(uid);
      await SessionManager.saveSession(
        uid: uid,
        email: (row?['email'] as String?) ?? '',
        provider: (row?['provider'] as String?) ?? 'password',
      );
      _goToDashboard(isOnline: false);
    }
  }

  Future<void> _offerBiometricEnroll(String uid) async {
    if (!mounted) return;
    if (!await BiometricAuthService.isSupported()) return;
    if (await BiometricAuthService.isEnrolled()) return;
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick unlock?'),
        content: const Text(
          'Use your fingerprint to get back in quickly, even offline if you forget your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (enable == true && mounted) {
      await BiometricAuthService.enroll(uid);
      unawaited(_checkBiometric());
    }
  }

  void _goToDashboard({required bool isOnline}) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AppShell(offlineMode: !isOnline)),
    );
  }

  void _togglePassword() {
    setState(() {
      _showPassword = !_showPassword;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return SafeArea(
      child: Scaffold(
        backgroundColor: colors.base,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
            child: _LoginForm(
              formKey: _formKey,
              emailController: _emailController,
              passwordController: _passwordController,
              showPassword: _showPassword,
              showStorageNotice: _showStorageNotice,
              errorMessage: _errorMessage,
              googleFailure: _lastGoogleFailure,
              showGoogleFailureDetails: _showGoogleFailureDetails,
              isLoading: _isLoading,
              showBiometric: _biometricReady,
              colors: colors,
              onTogglePassword: _togglePassword,
              onToggleGoogleDetails: () => setState(
                () => _showGoogleFailureDetails = !_showGoogleFailureDetails,
              ),
              onLogin: _login,
              onGoogleSignIn: _signInWithGoogle,
              onGoogleLongPress: _showGoogleDiagnostics,
              onBiometricUnlock: _unlockWithBiometrics,
              onForgotPassword: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              onCreateAccount: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool showPassword;
  final bool showStorageNotice;
  final String? errorMessage;
  final GoogleSignInFailure? googleFailure;
  final bool showGoogleFailureDetails;
  final bool isLoading;
  final bool showBiometric;
  final ThemeColors colors;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleGoogleDetails;
  final VoidCallback onLogin;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onGoogleLongPress;
  final VoidCallback onBiometricUnlock;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.showPassword,
    required this.showStorageNotice,
    this.errorMessage,
    this.googleFailure,
    this.showGoogleFailureDetails = false,
    required this.isLoading,
    required this.showBiometric,
    required this.colors,
    required this.onTogglePassword,
    required this.onToggleGoogleDetails,
    required this.onLogin,
    required this.onGoogleSignIn,
    required this.onGoogleLongPress,
    required this.onBiometricUnlock,
    required this.onForgotPassword,
    required this.onCreateAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            if (!AppConfig.googleConfigured)
              _GoogleConfigBanner(
                colors: colors,
                message:
                    AppConfig.googleConfigError ??
                    'Google sign-in is not configured.',
              ),
            if (showStorageNotice) _StorageUpgradeNotice(colors: colors),
            Center(
              child: Text(
                'AgentA',
                style: AppTypography.display.copyWith(color: colors.ink),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Sign in to continue',
                style: AppTypography.subtitle.copyWith(color: colors.subtext),
              ),
            ),
            const SizedBox(height: 44),
            Text(
              "Email",
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.inputRadius,
                boxShadow: AppShadows.well,
              ),
              child: SystemKeyboardTextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: AppTypography.body.copyWith(color: colors.ink),
                validator: AuthService.validateEmail,
                decoration: InputDecoration(
                  hintText: "Email",
                  hintStyle: AppTypography.body.copyWith(color: colors.subtext),
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: colors.subtext,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: colors.base,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Password",
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.inputRadius,
                boxShadow: AppShadows.well,
              ),
              child: SystemKeyboardTextFormField(
                controller: passwordController,
                obscureText: !showPassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                style: AppTypography.body.copyWith(color: colors.ink),
                validator: AuthService.validatePassword,
                decoration: InputDecoration(
                  hintText: "Password",
                  hintStyle: AppTypography.body.copyWith(color: colors.subtext),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: colors.subtext,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: colors.base,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      showPassword ? Icons.visibility_off : Icons.visibility,
                      color: colors.subtext,
                      size: 20,
                    ),
                    tooltip: showPassword ? 'Hide password' : 'Show password',
                    onPressed: onTogglePassword,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onForgotPassword,
                child: Text(
                  "Forgot Password?",
                  style: AppTypography.body.copyWith(color: colors.accentInk),
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: colors.base,
                  borderRadius: AppRadius.bannerRadius,
                  boxShadow: AppShadows.raised,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.error_outline,
                            color: AppColors.errorText,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: AppTypography.label.copyWith(
                              color: colors.errorText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (googleFailure != null) ...[
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 48),
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: onToggleGoogleDetails,
                        child: Text(
                          showGoogleFailureDetails
                              ? 'Hide details'
                              : 'Show details',
                          style: AppTypography.body.copyWith(
                            color: colors.accentInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (showGoogleFailureDetails)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: colors.base,
                            borderRadius: AppRadius.chipRadius,
                          ),
                          child: SelectableText(
                            'code: ${googleFailure!.code}\n'
                            'detail: ${googleFailure!.detail ?? '(none)'}\n'
                            'hint: ${googleFailure!.hint}',
                            style: AppTypography.labelSm.copyWith(
                              color: colors.errorText,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonRadius,
                boxShadow: AppShadows.raised,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onLogin,
                  // Loading = inset + spinner only (§5): icon and label are
                  // replaced together, never stacked with the spinner.
                  child: isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onAccent,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.login, color: colors.onAccent, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            const Text("Sign In"),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonRadius,
                boxShadow: AppShadows.raised,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : onGoogleSignIn,
                  onLongPress: onGoogleLongPress,
                  icon: Icon(
                    Icons.g_mobiledata_rounded,
                    size: 28,
                    color: colors.subtext,
                  ),
                  label: const Text("Continue with Google"),
                ),
              ),
            ),
            if (showBiometric) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.buttonRadius,
                  boxShadow: AppShadows.raised,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onBiometricUnlock,
                    icon: Icon(Icons.fingerprint, color: colors.subtext),
                    label: const Text("Unlock with fingerprint"),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonRadius,
                boxShadow: AppShadows.raised,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: onCreateAccount,
                  icon: Icon(Icons.person_add, color: colors.subtext),
                  label: const Text("Create Account"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
