class UserProfileModel {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String recoveryCode;
  final DateTime? createdAt;

  UserProfileModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.recoveryCode,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'email': email,
    'photo_url': photoUrl,
    'recovery_code': recoveryCode,
    'created_at': createdAt?.millisecondsSinceEpoch,
  };

  factory UserProfileModel.fromMap(Map<String, dynamic> map, String uid) =>
    UserProfileModel(
      uid: uid,
      displayName: map['displayName'] ?? map['display_name'] ?? '',
      email: map['email'] ?? '',
      photoUrl: map['photo_url'],
      recoveryCode: map['recoveryCode'] ?? map['recovery_code'] ?? '',
      createdAt: _parseCreatedAt(map['created_at']),
    );

  static DateTime? _parseCreatedAt(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  UserProfileModel copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
    String? recoveryCode,
    DateTime? createdAt,
  }) {
    return UserProfileModel(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      recoveryCode: recoveryCode ?? this.recoveryCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
