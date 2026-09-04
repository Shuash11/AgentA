// ignore_for_file: empty_catches
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/user_profile_model.dart';
import '../services/auth/auth_service.dart';

class UserRepository {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<void> createUserProfile(String uid, String email,
      String displayName, String recoveryCode) async {
    await _db.from('profiles').upsert({
      'id': uid,
      'email': email,
      'display_name': displayName,
      'recovery_code': recoveryCode,
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

  static Future<String> getRecoveryCode() async {
    final uid = AuthService.currentUser?.id;
    if (uid == null) {
      throw Exception('No user logged in');
    }
    final row =
        await _db.from('profiles').select('recovery_code').eq('id', uid).maybeSingle();
    final recoveryCode = row?['recovery_code'] as String?;
    if (recoveryCode == null || recoveryCode.isEmpty) {
      throw Exception('Recovery code not found');
    }
    return recoveryCode;
  }

  static Future<bool> verifyRecoveryCode(String entered) async {
    final stored = await getRecoveryCode();
    return entered.trim().toUpperCase() == stored.toUpperCase();
  }
}
