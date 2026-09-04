// ignore_for_file: empty_catches
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../../services/auth/auth_service.dart';

class SecurityService {
  static SupabaseClient get _db => Supabase.instance.client;

  static String generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  static Future<String> getRecoveryCode() async {
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

  static Future<bool> verifyRecoveryCode(String entered) async {
    final stored = await getRecoveryCode();
    return entered.trim().toUpperCase() == stored.toUpperCase();
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
