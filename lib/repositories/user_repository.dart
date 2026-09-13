import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/user_profile_model.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/recovery_code_hasher.dart';

class UserRepository {
  static SupabaseClient get _db => Supabase.instance.client;

  // H8: raw recovery codes are shown once at creation only. What is
  // persisted (Supabase `recovery_code` column + local DB) is the SHA-256
  // hash. Target is a server-side RPC `verify_recovery_code` so the hash
  // never needs client-side comparison; until the RPC lands, compare
  // hashes for a single row (never a full-table fetch).

  static Future<void> createUserProfile(String uid, String email,
      String displayName, String recoveryCode) async {
    await _db.from('profiles').upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'recovery_code': RecoveryCodeHasher.hash(recoveryCode),
    });
  }

  /// Claim path for accounts first created offline: the local row only ever
  /// held the recovery-code *hash* (H8), so store that hash verbatim instead
  /// of hashing again — otherwise the code the user saved would stop matching.
  static Future<void> createUserProfileWithRecoveryHash(
      String uid, String email, String displayName, String recoveryCodeHash) async {
    await _db.from('profiles').upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'recovery_code': recoveryCodeHash,
    });
  }

  static Future<UserProfileModel?> getUserProfile(String uid) async {
    final row =
        await _db.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) return null;
    return UserProfileModel.fromMap(Map<String, dynamic>.from(row), uid);
  }

  static Future<void> updateDisplayName(
      String uid, String displayName) async {
    await _db
        .from('profiles')
        .update({'display_name': displayName}).eq('id', uid);
    await AuthService.updateDisplayName(displayName);
  }

  static Future<String> getRecoveryCodeHash() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      throw Exception('No user logged in');
    }
    final row =
        await _db.from('profiles').select('recovery_code').eq('id', uid).maybeSingle();
    final hash = row?['recovery_code'] as String?;
    if (hash == null || hash.isEmpty) {
      throw Exception('Recovery code not found');
    }
    return hash;
  }

  /// Preferred server-side verification stub (H8). Replace the body with
  /// `await _db.rpc('verify_recovery_code', params: {...})` once the
  /// function in supabase/migrations/*_rls.sql is deployed; never trust
  /// a client-supplied userId — the RPC must use auth.uid().
  static Future<bool> verifyRecoveryCodeViaRpc(String entered) async {
    try {
      final storedHash = await getRecoveryCodeHash();
      return RecoveryCodeHasher.verify(entered, storedHash);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[UserRepository] verifyRecoveryCodeViaRpc failed: $e | $stack');
      return false;
    }
  }

  static Future<bool> verifyRecoveryCode(String entered) {
    return verifyRecoveryCodeViaRpc(entered);
  }
}
