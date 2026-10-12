class ChatActivityState {
  final bool isTyping;
  final bool isInitializingModel;
  final bool isLoadingMessages;

  const ChatActivityState({
    this.isTyping = false,
    this.isInitializingModel = false,
    this.isLoadingMessages = true,
  });

  ChatActivityState copyWith({
    bool? isTyping,
    bool? isInitializingModel,
    bool? isLoadingMessages,
  }) {
    return ChatActivityState(
      isTyping: isTyping ?? this.isTyping,
      isInitializingModel: isInitializingModel ?? this.isInitializingModel,
      isLoadingMessages: isLoadingMessages ?? this.isLoadingMessages,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatActivityState &&
        other.isTyping == isTyping &&
        other.isInitializingModel == isInitializingModel &&
        other.isLoadingMessages == isLoadingMessages;
  }

  @override
  int get hashCode =>
      Object.hash(isTyping, isInitializingModel, isLoadingMessages);
}
