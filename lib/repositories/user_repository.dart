import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/models/user_profile_model.dart';

class UserRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> createUserProfile(String uid, String email, String displayName, String recoveryCode) async {
    await _db.collection('users').doc(uid).set({
      'displayName': displayName,
      'email': email,
      'recoveryCode': recoveryCode,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<UserProfileModel?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfileModel.fromMap(doc.data()!, uid);
  }

  static Future<void> updateDisplayName(String uid, String displayName) async {
    await _db.collection('users').doc(uid).update({'displayName': displayName});
    await _auth.currentUser?.updateDisplayName(displayName);
  }

  static Future<String> getRecoveryCode() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('No user logged in');
    }
    final doc = await _db.collection('users').doc(uid).get();
    final recoveryCode = doc.data()?['recoveryCode'] as String?;
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