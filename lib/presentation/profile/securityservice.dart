import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth/auth_service.dart';

class SecurityService {
  static SupabaseClient get _db => Supabase.instance.client;

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
