class ChatSessionModel {
  final String id;
  final String userId;
  final String title;
  final String lastMessage;
  final DateTime updatedAt;
  int unread;
  bool isSynced;
  bool isDeleted;

  ChatSessionModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.lastMessage,
    required this.updatedAt,
    this.unread = 0,
    this.isSynced = false,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'last_message': lastMessage,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'unread': unread,
    'is_synced': isSynced ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
  };

  factory ChatSessionModel.fromMap(Map<String, dynamic> map) =>
      ChatSessionModel(
        id: map['id'] as String? ?? '',
        userId: map['user_id'] as String? ?? '',
        title: map['title'] as String? ?? '',
        lastMessage: map['last_message'] as String? ?? '',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int? ?? 0),
        unread: map['unread'] as int? ?? 0,
        isSynced: map['is_synced'] == 1,
        isDeleted: map['is_deleted'] == 1,
      );

  ChatSessionModel copyWith({bool? isSynced, bool? isDeleted, String? lastMessage, String? title, DateTime? updatedAt}) {
    return ChatSessionModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      unread: unread,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}