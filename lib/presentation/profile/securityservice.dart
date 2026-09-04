import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class SecurityService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  static Future<String> getRecoveryCode() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return '';
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return '';
      return doc.data()?['recoveryCode'] as String? ?? '';
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
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _db.collection('users').doc(uid).delete();
        await _auth.currentUser?.delete();
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}