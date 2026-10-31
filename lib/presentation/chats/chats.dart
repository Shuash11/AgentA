import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/chat_error_classifier.dart';
import '../../core/utils/connectivity_service.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../theme/app_theme.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/ai_model.dart';
import '../../services/ai/device_capabilities.dart';
import '../../services/ai/gemma_service.dart';
import '../../services/ai/model_download_service.dart';
import '../../data/local/offline_model_dao.dart';
import '../shared/offline_model_banner.dart';
import '../ai/download_prompt_screen.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/chat_session_model.dart';
import '../../repositories/message_repository.dart';
import '../../repositories/chat_repository.dart';
import '../../data/local/local_chat_dao.dart';
import 'widgets/chat_activity_state.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_screen_app_bar.dart';
import 'widgets/chat_timeline_view.dart';
import 'widgets/model_picker_sheet.dart';

/// The primary action the offline-model affordance offers.
enum OfflineModelAction {
  /// The model is installed but not loaded → retry the load. The download
  /// screen would be a no-op for an installed model.
  retryLoad,

  /// The model is genuinely not installed → open the download screen.
  getModel,

  /// The device cannot run the model at all (cycle-40 P1) → no download and
  /// no retry: both could never succeed, so the card shows the honest
  /// incompatible-device message and nothing else.
  incompatibleDevice,
}

/// Resolves the chat card's primary action from the model state.
///
/// cycle-38 P6: an INSTALLED-but-not-loaded model must offer RETRY LOAD.
/// Routing it to the download screen produced the no-op loop the user hit
/// ("Get model" → "Download Complete!" → back to a broken chat) and could
/// start a spurious 2.6 GB re-download of an asset the device already has.
/// The download screen stays reserved for a model that is genuinely missing.
///
/// The durable install marker is the primary signal: it is the one the S7
/// constraint is written against, and it survives a restart — the
/// in-memory download-service status cannot answer it after one.
///
/// cycle-40 P1: a device that cannot run the model offers NO action. The
/// same holds when the engine itself classified the failure as an ABI
/// mismatch — the failure class is the release-visible evidence that a
/// retry cannot help.
OfflineModelAction resolveOfflineModelAction({
  required OfflineModelState state,
  required bool isInstalled,
  bool isDeviceCompatible = true,
  OfflineModelFailureClass? failureClass,
}) {
  // An incompatible device can neither load nor download the model.
  if (!isDeviceCompatible ||
      failureClass == OfflineModelFailureClass.unsupportedAbi) {
    return OfflineModelAction.incompatibleDevice;
  }

  // The model is usable — there is nothing to recover. The card is only
  // rendered for a failed attempt, so this is a safe default rather than a
  // reachable UI state.
  if (state == OfflineModelState.loaded) return OfflineModelAction.retryLoad;

  // Installed → the LOAD is what failed → retry the load. Never the
  // download screen: that re-downloads an asset the device already has.
  if (isInstalled) return OfflineModelAction.retryLoad;

  // Not installed → the model is genuinely missing → the download.
  // `modelMissing` is the service's explicit verdict, `idle` means no load
  // attempt ran yet, and a `loadFailed` without an installed asset means the
  // asset is gone too.
  return OfflineModelAction.getModel;
}

class Chats extends StatefulWidget {
  final String title;
  final String chatId;
  final bool isNew;
  final bool offlineMode;

  const Chats({
    super.key,
    this.title = 'Chat With AgentA',
    this.chatId = '',
    this.isNew = false,
    this.offlineMode = false,
  });

  @override
  State<Chats> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<Chats> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<List<ChatMessageModel>> _messagesNotifier =
      ValueNotifier<List<ChatMessageModel>>(const []);
  final ValueNotifier<ChatActivityState> _activityNotifier =
      ValueNotifier<ChatActivityState>(const ChatActivityState());
  StreamSubscription<String>? _generationSubscription;
  StreamSubscription? _connectivitySubscription;
  bool _isGenerationCancelled = false;
  int _activeGenerationId = 0;
  bool _scrollScheduled = false;

  String? _partialAiMsgId;
  late AIService _aiService;
  late MessageRepository _messageRepo;
  late ChatRepository _chatRepo;
  late LocalChatDao _localChatDao;
  bool _initialized = false;
  bool _wasOnline = true;

  String _streamingBuffer = '';
  Timer? _streamingTimer;
  bool _streamingUpdateScheduled = false;

  List<ChatMessageModel> get _messages => _messagesNotifier.value;
  bool get _isTyping => _activityNotifier.value.isTyping;
  bool get _isImageGenerationModel {
    final modelName = _aiService.activeModel.name.toLowerCase();
    return modelName.contains('pollinations') || modelName.contains('image');
  }

  bool get _isOfflineThinking {
    return _aiService.activeModel == AIModel.gemma;
  }

  @override
  void initState() {
    super.initState();
  }

  void _setMessages(List<ChatMessageModel> messages) {
    _messagesNotifier.value = List<ChatMessageModel>.unmodifiable(messages);
  }

  void _setActivity({
    bool? isTyping,
    bool? isInitializingModel,
    bool? isLoadingMessages,
  }) {
    final next = _activityNotifier.value.copyWith(
      isTyping: isTyping,
      isInitializingModel: isInitializingModel,
      isLoadingMessages: isLoadingMessages,
    );

    if (next != _activityNotifier.value) {
      _activityNotifier.value = next;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _aiService = context.read<AIService>();
    _messageRepo = context.read<MessageRepository>();
    _chatRepo = context.read<ChatRepository>();
    _localChatDao = LocalChatDao.instance;

    final connectivity = context.read<ConnectivityCubit>();
    _wasOnline = connectivity.state.isOnline;

    _connectivitySubscription = connectivity.statusStream.listen((status) {
      final isNowOnline = status == InternetStatus.online;
      if (_wasOnline && !isNowOnline && _isTyping) {
        _handleConnectivityLost();
      }
      _wasOnline = isNowOnline;
    });

    unawaited(_initializeChat());
  }

  Future<void> _initializeChat() async {
    if (widget.isNew) {
      await _createChatIfNew();
    } else {
      final uid = await _localChatDao.getUserId();
      final existing = await _chatRepo.getChat(widget.chatId);
      if (existing != null &&
          existing.userId.isNotEmpty &&
          uid.isNotEmpty &&
          existing.userId != uid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have access to this chat.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
        return;
      }
    }

    try {
      await _aiService.resetOfflineSession();
    } catch (e) {
      // L20: reset failures are logged instead of silently swallowed;
      // they are non-fatal (the chat can still proceed offline).
      if (kDebugMode) debugPrint('[Chats] resetOfflineSession failed: $e');
    }

    _setActivity(isLoadingMessages: true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final localMsgs = await _messageRepo.getLocalMessages(widget.chatId);
      if (!mounted) return;

      if (localMsgs.isNotEmpty) {
        _setMessages(localMsgs);
        _setActivity(isLoadingMessages: false);
      } else {
        _setActivity(isLoadingMessages: false);
        if (widget.isNew) {
          final greeting = ChatMessageModel(
            id: const Uuid().v4(),
            chatId: widget.chatId,
            text: GemmaService.greetingText,
            isUser: false,
            timestamp: DateTime.now(),
          );
          _setMessages([..._messages, greeting]);
          await _messageRepo.saveMessage(greeting);
        }
      }

      unawaited(_refreshRemoteInBackground());
    });
  }

  Future<void> _refreshRemoteInBackground() async {
    final remoteMsgs = await _messageRepo.refreshMessagesFromRemote(
      widget.chatId,
    );
    if (!mounted || remoteMsgs.isEmpty) return;

    final Map<String, ChatMessageModel> mergedMap = {
      for (var m in _messages) m.id: m,
    };

    for (final remote in remoteMsgs) {
      final local = mergedMap[remote.id];
      if (local == null) {
        mergedMap[remote.id] = remote;
      } else if (local.isSynced) {
        if (local.text != remote.text || local.timestamp != remote.timestamp) {
          mergedMap[remote.id] = remote;
        }
      }
    }

    final merged = mergedMap.values.toList();
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (!_listsEqual(_messages, merged)) {
      _setMessages(merged);
    }
  }

  bool _listsEqual(List<ChatMessageModel> a, List<ChatMessageModel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].text != b[i].text ||
          a[i].timestamp != b[i].timestamp) {
        return false;
      }
    }
    return true;
  }

  Future<void> _createChatIfNew() async {
    if (!widget.isNew) return;

    final userId = await _localChatDao.getUserId();
    final chat = ChatSessionModel(
      id: widget.chatId,
      userId: userId,
      title: 'New Chat',
      lastMessage: '',
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    await _chatRepo.createChat(chat);
  }

  Future<void> _updateChatSession(String userMessage) async {
    final chat = await _chatRepo.getChat(widget.chatId);
    if (chat == null) return;

    final title = userMessage.length > 30
        ? '${userMessage.substring(0, 30)}...'
        : userMessage;

    final updatedChat = chat.copyWith(
      title: title,
      lastMessage: userMessage,
      updatedAt: DateTime.now(),
    );
    await _chatRepo.updateChat(updatedChat);
  }

  @override
  void dispose() {
    unawaited(_generationSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    _streamingTimer?.cancel();
    _messagesNotifier.dispose();
    _activityNotifier.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleConnectivityLost() {
    if (!mounted || !_isTyping) return;
    unawaited(_generationSubscription?.cancel());
    _generationSubscription = null;
    _aiService.cancelActiveGeneration();

    _isGenerationCancelled = true;
    if (_partialAiMsgId != null) {
      _setMessages(
        _messages.where((msg) => msg.id != _partialAiMsgId).toList(),
      );
      _partialAiMsgId = null;
    }
    _setActivity(isTyping: false, isInitializingModel: false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection lost. Please try again when back online.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isTyping) return;

    final generationId = ++_activeGenerationId;

    final userMsg = ChatMessageModel(
      id: const Uuid().v4(),
      chatId: widget.chatId,
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    _setMessages([..._messages, userMsg]);
    _controller.clear();
    _isGenerationCancelled = false;
    _setActivity(isTyping: true, isInitializingModel: true);

    _scrollToBottom(animated: false);

    await _messageRepo.saveMessage(userMsg);
    await _updateChatSession(text);

    _streamingBuffer = '';
    _streamingTimer?.cancel();
    _streamingUpdateScheduled = false;
    String? aiMsgId;

    void scheduleStreamingUpdate() {
      if (_streamingUpdateScheduled) return;
      _streamingUpdateScheduled = true;
      _streamingTimer?.cancel();
      final currentMessage = _messages.isNotEmpty && !_messages.last.isUser
          ? _messages.last
          : null;
      if (currentMessage == null) {
        _streamingUpdateScheduled = false;
        return;
      }
      _streamingTimer = Timer(const Duration(milliseconds: 100), () {
        if (!mounted ||
            _isGenerationCancelled ||
            generationId != _activeGenerationId) {
          return;
        }
        _streamingUpdateScheduled = false;
        final messageIndex = _messages.indexWhere(
          (msg) => msg.id == currentMessage.id,
        );
        if (messageIndex == -1) return;

        final messages = [..._messages];
        messages[messageIndex] = ChatMessageModel(
          id: currentMessage.id,
          chatId: currentMessage.chatId,
          text: _streamingBuffer,
          isUser: false,
          timestamp: currentMessage.timestamp,
        );
        _setMessages(messages);
        _scrollToBottom(animated: false);
      });
    }

    try {
      await _generationSubscription?.cancel();

      final stream = _aiService.sendMessageStream(
        history: _messages,
        newMessage: text,
      );

      _generationSubscription = stream.listen(
        (chunk) {
          if (!mounted ||
              _isGenerationCancelled ||
              generationId != _activeGenerationId) {
            return;
          }

          _streamingBuffer += chunk;

          if (_messages.isEmpty || _messages.last.isUser) {
            _setActivity(isInitializingModel: false);
            aiMsgId = const Uuid().v4();
            _partialAiMsgId = aiMsgId;
            _setMessages([
              ..._messages,
              ChatMessageModel(
                id: aiMsgId!,
                chatId: widget.chatId,
                text: chunk,
                isUser: false,
                timestamp: DateTime.now(),
              ),
            ]);
            _scrollToBottom(animated: false);
          } else {
            scheduleStreamingUpdate();
          }
        },
        onDone: () {
          if (!mounted ||
              _isGenerationCancelled ||
              generationId != _activeGenerationId) {
            return;
          }
          _streamingTimer?.cancel();
          _setActivity(isInitializingModel: false);
          if (aiMsgId != null &&
              _messages.isNotEmpty &&
              !_messages.last.isUser) {
            final lastMsg = _messages.last;
            final messages = [..._messages];
            messages[messages.length - 1] = ChatMessageModel(
              id: lastMsg.id,
              chatId: lastMsg.chatId,
              text: _streamingBuffer.isEmpty ? lastMsg.text : _streamingBuffer,
              isUser: false,
              timestamp: lastMsg.timestamp,
            );
            _setMessages(messages);
            _scrollToBottom(animated: false);
          }
          unawaited(_completeGeneration(generationId));
        },
        onError: (error) {
          if (!mounted ||
              _isGenerationCancelled ||
              generationId != _activeGenerationId) {
            return;
          }
          unawaited(_handleGenerationError(error));
        },
        cancelOnError: true,
      );
    } catch (e) {
      unawaited(_handleGenerationError(e));
    }
  }

  Future<void> _completeGeneration(int generationId) async {
    if (_isGenerationCancelled ||
        !mounted ||
        generationId != _activeGenerationId) {
      return;
    }

    _partialAiMsgId = null;
    _setActivity(isTyping: false, isInitializingModel: false);

    if (_messages.isEmpty) return;
    final finalMsg = _messages.last;
    await _messageRepo.saveMessage(
      ChatMessageModel(
        id: finalMsg.id,
        chatId: finalMsg.chatId,
        text: finalMsg.text,
        isUser: false,
        timestamp: finalMsg.timestamp,
      ),
    );
  }

  void _stopGeneration() async {
    final stoppedGenerationId = _activeGenerationId;
    _activeGenerationId++;
    _isGenerationCancelled = true;

    await _generationSubscription?.cancel();
    _generationSubscription = null;

    _aiService.cancelActiveGeneration();

    if (!mounted) return;
    if (_partialAiMsgId != null && stoppedGenerationId < _activeGenerationId) {
      _setMessages(
        _messages.where((msg) => msg.id != _partialAiMsgId).toList(),
      );
      _partialAiMsgId = null;
    }
    _setActivity(isTyping: false, isInitializingModel: false);
  }

  Future<void> _retryImageWithHuggingFace(String messageId) async {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index == -1 || !mounted) return;

    String prompt = '';
    for (int i = index - 1; i >= 0; i--) {
      if (_messages[i].isUser && _messages[i].text.trim().isNotEmpty) {
        prompt = _messages[i].text.trim();
        break;
      }
    }
    if (prompt.isEmpty) {
      final failedUrl = _messages[index].text.trim();
      final match = RegExp(
        r'pollinations\.ai/prompt/([^?]+)',
      ).firstMatch(failedUrl);
      if (match != null) {
        prompt = Uri.decodeComponent(match.group(1)!);
      }
    }
    if (prompt.isEmpty || !mounted) return;

    _setActivity(isTyping: true, isInitializingModel: true);
    try {
      final localPath = await _aiService.generateImageFallback(prompt);
      if (!mounted) return;
      final messages = [..._messages];
      final currentIndex = messages.indexWhere((msg) => msg.id == messageId);
      if (currentIndex != -1) {
        final old = messages[currentIndex];
        final updated = ChatMessageModel(
          id: old.id,
          chatId: old.chatId,
          text: localPath,
          isUser: false,
          timestamp: old.timestamp,
        );
        messages[currentIndex] = updated;
        _setMessages(messages);
        await _messageRepo.saveMessage(updated);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ChatErrorClassifier.friendly(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setActivity(isTyping: false, isInitializingModel: false);
      }
    }
  }

  Future<void> _handleGenerationError(Object error) async {
    if (!mounted) return;

    final rawText = error.toString();
    final errorText = ChatErrorClassifier.friendly(rawText);
    final needsDownloadAction = ChatErrorClassifier.isOfflineNotReady(rawText);
    final partialAiMsgId = _partialAiMsgId;
    final errorMsg = ChatMessageModel(
      id: const Uuid().v4(),
      chatId: widget.chatId,
      text: errorText,
      isUser: false,
      timestamp: DateTime.now(),
    );

    _partialAiMsgId = null;
    final messages = partialAiMsgId == null
        ? [..._messages, errorMsg]
        : [..._messages.where((msg) => msg.id != partialAiMsgId), errorMsg];
    _setMessages(messages);
    _setActivity(isTyping: false, isInitializingModel: false);

    _scrollToBottom(animated: true);

    if (!mounted) return;
    if (needsDownloadAction) {
      // The affordance follows the model STATE: an installed-but-unloaded
      // model gets RETRY LOAD, a genuinely missing model gets GET MODEL.
      final action = await _resolveOfflineAction(context);
      if (!mounted) return;
      _showOfflineActionSnackBar(action);
    }
  }

  /// Resolves which offline-model affordance the card offers.
  ///
  /// The durable install marker decides (S7): an installed model always
  /// routes to RETRY LOAD. When the marker cannot be read, the service's
  /// own verdict is the fallback — a failed load must never leave the user
  /// without an affordance. A device that cannot run the model has no
  /// affordance at all (cycle-40 P1).
  Future<OfflineModelAction> _resolveOfflineAction(BuildContext context) async {
    final gemmaService = context.read<GemmaService>();
    final compatible = await DeviceCapabilities.isOfflineAiSupported();
    try {
      final installed = await OfflineModelDao().isModelInstalled();
      return resolveOfflineModelAction(
        state: gemmaService.state,
        isInstalled: installed,
        isDeviceCompatible: compatible,
        failureClass: gemmaService.lastFailureClass,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Chats] offline model install state unavailable: $e');
      }
      if (!compatible ||
          gemmaService.lastFailureClass ==
              OfflineModelFailureClass.unsupportedAbi) {
        return OfflineModelAction.incompatibleDevice;
      }
      return gemmaService.state == OfflineModelState.modelMissing
          ? OfflineModelAction.getModel
          : OfflineModelAction.retryLoad;
    }
  }

  /// Shows the offline-model affordance for the current state.
  ///
  /// An incompatible device gets the honest message and NO action: no
  /// download, no retry (cycle-40 P1).
  void _showOfflineActionSnackBar(OfflineModelAction action) {
    final label = _offlineActionLabel(action);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          label == null
              ? DeviceCapabilities.incompatibleDeviceMessage
              : ChatErrorClassifier.offlineNotReadyMessage,
        ),
        behavior: SnackBarBehavior.floating,
        action: label == null
            ? null
            : SnackBarAction(
                label: label,
                onPressed: () => unawaited(_runOfflineAction(action)),
              ),
      ),
    );
  }

  /// The label of the affordance, or null when the state offers none.
  String? _offlineActionLabel(OfflineModelAction action) {
    switch (action) {
      case OfflineModelAction.retryLoad:
        return 'Retry load';
      case OfflineModelAction.getModel:
        return 'Get model';
      case OfflineModelAction.incompatibleDevice:
        return null;
    }
  }

  /// Runs the resolved offline-model affordance.
  Future<void> _runOfflineAction(OfflineModelAction action) async {
    switch (action) {
      case OfflineModelAction.retryLoad:
        await _retryLoadModel();
        return;
      case OfflineModelAction.getModel:
        _pushDownloadScreen();
        return;
      case OfflineModelAction.incompatibleDevice:
        // Nothing can be done for an incompatible device — say so honestly
        // instead of offering an action that cannot succeed (cycle-40 P1).
        _showOfflineActionSnackBar(action);
        return;
    }
  }

  /// Retries the offline-model load.
  ///
  /// Honest feedback only: the load reports its progress, a failed retry
  /// surfaces the service's friendly reason and the retry affordance stays
  /// available — no endless spinner and no fake success (cycle-38 P6,
  /// S4-safe). The raw exception never reaches the UI copy.
  Future<void> _retryLoadModel() async {
    final messenger = ScaffoldMessenger.of(context);
    final gemmaService = context.read<GemmaService>();

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Loading offline model...'),
        behavior: SnackBarBehavior.floating,
        // The first load of a multi-gigabyte model is slow — the progress
        // notice must outlive it instead of vanishing mid-load and leaving
        // the user with no feedback (and no affordance).
        duration: Duration(seconds: 120),
      ),
    );

    try {
      await gemmaService.loadInstalled();
      if (!mounted) return;
      // The successful load rewrote the DAO row to ready; re-sync the
      // download service so the offline banner stops claiming the model is
      // missing (its in-memory status was computed from the error row).
      // checkModelExists() only reads state — it never downloads.
      await context.read<ModelDownloadService>().checkModelExists();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('AgentA Offline AI is ready.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Chats] offline model load retry failed: $e');
      }
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      final action = await _resolveOfflineAction(context);
      if (!mounted) return;
      final label = _offlineActionLabel(action);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            label == null
                ? DeviceCapabilities.incompatibleDeviceMessage
                : (gemmaService.lastError ?? 'Offline model failed to load.'),
          ),
          behavior: SnackBarBehavior.floating,
          action: label == null
              ? null
              : SnackBarAction(
                  label: label,
                  onPressed: () => unawaited(_runOfflineAction(action)),
                ),
        ),
      );
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 80;
  }

  void _scrollToBottom({bool animated = true}) {
    if (_scrollScheduled) return;
    if (!_isNearBottom) return;

    _scrollScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position.maxScrollExtent;
      if (animated && _isNearBottom) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    });
  }

  /// Opens the offline-model affordance for the current state.
  ///
  /// An INSTALLED but unloaded model must NOT open the download screen: that
  /// screen completes instantly for an installed model and used to be a
  /// no-op loop (cycle-38 P6). It retries the load instead.
  Future<void> _openDownloadScreen(BuildContext context) async {
    final action = await _resolveOfflineAction(context);
    if (!mounted) return;
    await _runOfflineAction(action);
  }

  void _pushDownloadScreen() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadPromptScreen(
          onSkip: () => Navigator.pop(context),
          onComplete: () {
            Navigator.pop(context);
          },
          isForcedGate: false,
        ),
      ),
    );
  }

  Future<void> _showModelPicker(BuildContext context, ThemeColors colors) {
    return showModelPickerSheet(
      context: context,
      colors: colors,
      aiService: _aiService,
      onModelSelected: (model) {
        if (_aiService.preferredModel == model) return;
        setState(() {
          _aiService.setPreferredModel(model);
        });
      },
      onDownloadRequested: () => unawaited(_openDownloadScreen(context)),
    );
  }

  void _handleBack() {
    if (widget.isNew && _messages.length > 1) {
      final firstUserMsg = _messages.firstWhere(
        (m) => m.isUser,
        orElse: () => ChatMessageModel(
          id: '',
          chatId: '',
          text: widget.title,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      final title = firstUserMsg.text.length > 30
          ? '${firstUserMsg.text.substring(0, 30)}...'
          : firstUserMsg.text;
      Navigator.pop(context, title);
      return;
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    return Scaffold(
      backgroundColor: colors.base,
      appBar: ChatScreenAppBar(
        title: widget.title,
        modelName: _aiService.currentModelName,
        colors: colors,
        onBack: _handleBack,
        onModelPickerTap: () => _showModelPicker(context, colors),
      ),
      body: Column(
        children: [
          OfflineModelBanner(
            onTap: () => unawaited(_openDownloadScreen(context)),
          ),
          Expanded(
            child: ChatTimelineView(
              messagesListenable: _messagesNotifier,
              activityListenable: _activityNotifier,
              scrollController: _scrollController,
              colors: colors,
              animateEmpty: widget.isNew,
              isImageGeneration: _isImageGenerationModel,
              isThinking: _isOfflineThinking,
              onImageFallback: _retryImageWithHuggingFace,
              fallbackAvailable: _aiService.isHuggingFaceAvailable,
            ),
          ),
          ValueListenableBuilder<ChatActivityState>(
            valueListenable: _activityNotifier,
            builder: (context, activity, _) {
              return ChatInputBar(
                controller: _controller,
                onSend: _sendMessage,
                onStop: _stopGeneration,
                colors: colors,
                isTyping: activity.isTyping,
              );
            },
          ),
        ],
      ),
    );
  }
}
