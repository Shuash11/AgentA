import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/chat_message_model.dart';

class ChatState {
  final List<ChatMessageModel> messages;
  final bool isTyping;
  final String? partialAiMsgId;
  final String? errorMessage;
  final bool isGenerationCancelled;
  final int activeGenerationId;

  const ChatState({
    this.messages = const [],
    this.isTyping = false,
    this.partialAiMsgId,
    this.errorMessage,
    this.isGenerationCancelled = false,
    this.activeGenerationId = 0,
  });

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    bool? isTyping,
    String? partialAiMsgId,
    String? errorMessage,
    bool? isGenerationCancelled,
    int? activeGenerationId,
    bool clearPartialAiMsgId = false,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      partialAiMsgId: clearPartialAiMsgId ? null : (partialAiMsgId ?? this.partialAiMsgId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isGenerationCancelled: isGenerationCancelled ?? this.isGenerationCancelled,
      activeGenerationId: activeGenerationId ?? this.activeGenerationId,
    );
  }
}

class ChatCubit extends Cubit<ChatState> {
  Timer? _debounceTimer;
  static const _chunkDebounceDuration = Duration(milliseconds: 100);

  ChatCubit() : super(const ChatState());

  void initializeWithMessages(List<ChatMessageModel> messages) {
    emit(state.copyWith(messages: messages));
  }

  void addGreeting(ChatMessageModel greeting) {
    emit(state.copyWith(messages: [...state.messages, greeting]));
  }

  void addUserMessage(ChatMessageModel message) {
    emit(state.copyWith(
      messages: [...state.messages, message],
      isTyping: true,
      isGenerationCancelled: false,
      activeGenerationId: state.activeGenerationId + 1,
    ));
  }

  void startAiMessage(String msgId) {
    final messages = List<ChatMessageModel>.from(state.messages);
    messages.add(ChatMessageModel(
      id: msgId,
      chatId: '',
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
    ));
    emit(state.copyWith(
      messages: messages,
      partialAiMsgId: msgId,
      isTyping: true,
    ));
  }

  void updateAiMessageChunk(String msgId, String chunk) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_chunkDebounceDuration, () {
      _updateAiMessage(msgId, chunk);
    });
  }

  void _updateAiMessage(String msgId, String text) {
    final messages = List<ChatMessageModel>.from(state.messages);
    final index = messages.indexWhere((m) => m.id == msgId);
    if (index != -1) {
      messages[index] = ChatMessageModel(
        id: msgId,
        chatId: messages[index].chatId,
        text: text,
        isUser: false,
        timestamp: messages[index].timestamp,
      );
      emit(state.copyWith(messages: messages));
    }
  }

  void completeAiMessage(String msgId, String finalText) {
    _debounceTimer?.cancel();
    final messages = List<ChatMessageModel>.from(state.messages);
    final index = messages.indexWhere((m) => m.id == msgId);
    if (index != -1) {
      messages[index] = ChatMessageModel(
        id: msgId,
        chatId: messages[index].chatId,
        text: finalText,
        isUser: false,
        timestamp: messages[index].timestamp,
      );
    }
    emit(state.copyWith(
      messages: messages,
      isTyping: false,
      clearPartialAiMsgId: true,
    ));
  }

  void removePartialMessage(String msgId) {
    final messages = state.messages.where((m) => m.id != msgId).toList();
    emit(state.copyWith(
      messages: messages,
      clearPartialAiMsgId: true,
    ));
  }

  void stopGeneration() {
    _debounceTimer?.cancel();
    final newGenerationId = state.activeGenerationId + 1;
    emit(state.copyWith(
      isGenerationCancelled: true,
      isTyping: false,
      activeGenerationId: newGenerationId,
      clearPartialAiMsgId: true,
    ));
  }

  void setError(String errorText, {String? partialToRemove}) {
    _debounceTimer?.cancel();
    var messages = List<ChatMessageModel>.from(state.messages);
    if (partialToRemove != null) {
      messages = messages.where((m) => m.id != partialToRemove).toList();
    }
    messages.add(ChatMessageModel(
      id: const Uuid().v4(),
      chatId: '',
      text: errorText,
      isUser: false,
      timestamp: DateTime.now(),
    ));
    emit(state.copyWith(
      messages: messages,
      isTyping: false,
      clearPartialAiMsgId: true,
    ));
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  int get nextGenerationId => state.activeGenerationId + 1;

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}