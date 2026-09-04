class ChatMessageModel {
  final String id;
  final String chatId;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  bool isSynced;
  bool isDeleted;

  ChatMessageModel({
    required this.id,
    required this.chatId,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isSynced = false,
    this.isDeleted = false,
  });

  bool get hasMarkdown => _computeHasMarkdown(text);

  Map<String, dynamic> toMap() => {
    'id': id,
    'chat_id': chatId,
    'text': text,
    'is_user': isUser ? 1 : 0,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'is_synced': isSynced ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
  };

  factory ChatMessageModel.fromMap(Map<String, dynamic> map) =>
      ChatMessageModel(
        id: map['id'] as String? ?? '',
        chatId: map['chat_id'] as String? ?? '',
        text: map['text'] as String? ?? '',
        isUser: (map['is_user'] as int?) == 1,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int? ?? 0),
        isSynced: map['is_synced'] == 1,
        isDeleted: map['is_deleted'] == 1,
      );

  ChatMessageModel copyWith({
    String? id,
    String? chatId,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  static bool _computeHasMarkdown(String text) {
    if (text.contains('```')) return true;
    if (text.contains('**') || text.contains('__')) return true;

    for (int i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '[') {
        if (i + 1 < text.length && text[i + 1] != ']') {
          int j = i + 1;
          while (j < text.length && text[j] != ']' && text[j] != '\n') {
            j++;
          }
          if (j < text.length && text[j] == ']' && j + 1 < text.length && text[j + 1] == '(') {
            return true;
          }
        }
      }
      if (c == '#') {
        if (i + 1 < text.length && text[i + 1] == ' ') return true;
        if (i == 0 || text[i - 1] == '\n') {
          int j = i + 1;
          while (j < text.length && _isDigit(text[j])) {
            j++;
          }
          if (j < text.length && text[j] == ' ') return true;
        }
      }
      if ((c == '-' || c == '*') && i + 1 < text.length && text[i + 1] == ' ') {
        if (i == 0 || text[i - 1] == '\n') return true;
      }
      if (c == '`') {
        if (i + 1 < text.length && text[i + 1] == '`') return true;
        if (i == 0 || text[i - 1] == '\n' || text[i - 1] == ' ' || text[i - 1] == '(') {
          int j = i + 1;
          while (j < text.length && text[j] != '`' && text[j] != '\n') {
            j++;
          }
          if (j < text.length && text[j] == '`') return true;
        }
      }
      if ((c == '*' || c == '_') &&
          i + 2 < text.length &&
          text[i + 1] != ' ' &&
          text[i + 1] != c) {
        int j = i + 2;
        while (j < text.length && text[j] != c && text[j] != '\n') {
          j++;
        }
        if (j < text.length && text[j] == c && text[j - 1] != ' ') {
          return true;
        }
      }
      if (c == '1' && i + 2 < text.length && text[i + 1] == '.' && text[i + 2] == ' ') {
        if (i == 0 || text[i - 1] == '\n') return true;
      }
      if (c == '>') {
        if (i == 0 || text[i - 1] == '\n') return true;
      }
    }
    return false;
  }

  static bool _isDigit(String c) {
    return c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  }
}