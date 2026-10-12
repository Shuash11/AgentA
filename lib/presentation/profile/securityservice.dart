import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../../services/auth/auth_service.dart';
import '../../services/auth/recovery_code_hasher.dart';

class SecurityService {
  static SupabaseClient get _db => Supabase.instance.client;

  static String generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(
      6,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  /// H8: returns the stored hash (single-row select by auth uid),
  /// never the raw code. Prefer RPC verification below.
  static Future<String> getRecoveryCodeHash() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) return '';
    try {
      final row = await _db
          .from('profiles')
          .select('recovery_code')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return '';
      return row['recovery_code'] as String? ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Server-side RPC stub — deploy `verify_recovery_code` (see
  /// supabase/migrations) and switch this body to `_db.rpc(...)`.
  static Future<bool> verifyRecoveryCode(String entered) async {
    final storedHash = await getRecoveryCodeHash();
    if (storedHash.isEmpty) return false;
    return RecoveryCodeHasher.verify(entered, storedHash);
  }

  static Future<bool> deleteAccount() async {
    try {
      final uid = AuthService.currentUser?.id;
      if (uid != null) {
        await _db.from('profiles').delete().eq('id', uid);
      }
      await AuthService.logout();
      return true;
    } catch (e) {
      return false;
    }
  }
}
