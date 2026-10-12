import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../shared/bottomnavbar.dart';
import '../shared/offline_model_banner.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../../core/utils/connectivity_service.dart';
import '../../theme/app_theme.dart';
import '../chats/chats.dart';
import '../../data/models/chat_session_model.dart';
import '../../data/local/local_chat_dao.dart';
import '../../repositories/chat_repository.dart';
import '../ai/download_prompt_screen.dart';

class Dashboard extends StatefulWidget {
  final bool offlineMode;
  final bool showBottomNav;
  final bool showBackButton;

  const Dashboard({
    super.key,
    this.offlineMode = false,
    this.showBottomNav = false,
    this.showBackButton = true,
  });

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<ChatSessionModel> _chats = [];
  bool _isLoading = true;
  String? _loadError;
  bool _initialized = false;
  bool _wasOnline = true;
  StreamSubscription? _connectivitySubscription;
  late final LocalChatDao _localChatDao;
  late final ChatRepository _chatRepo;

  static final Widget _dismissBackground = Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: AppRadius.cardRadius,
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Icon(Icons.delete, color: Colors.white, size: 20),
    ),
  );

  @override
  void initState() {
    super.initState();
    _localChatDao = LocalChatDao.instance;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _chatRepo = context.read<ChatRepository>();
    final connectivity = context.read<ConnectivityCubit>();
    _wasOnline = connectivity.state.isOnline;
    _connectivitySubscription = connectivity.statusStream.listen((status) {
      final isNowOnline = status == InternetStatus.online;
      if (!_wasOnline && isNowOnline && mounted) {
        _loadChats();
      }
      _wasOnline = isNowOnline;
    });
    _loadChats();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadChats() async {
    if (!mounted) return;
    setState(() {
      _loadError = null;
      if (_chats.isEmpty) {
        _isLoading = true;
      }
    });
    try {
      final userId = await _localChatDao.getUserId();
      final chats = await _chatRepo.getChatsForUser(userId);
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Dashboard] load chats failed: $e');
      }
      if (mounted) {
        // Friendly static text only — raw detail stays in logs (error hygiene).
        setState(() {
          _isLoading = false;
          _loadError = "Couldn't load your conversations.";
        });
      }
    }
  }

  void _newChat() async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Chats(
          title: 'New Chat',
          chatId: newId,
          isNew: true,
          offlineMode: widget.offlineMode,
        ),
      ),
    );
    if (mounted) _loadChats();
  }

  void _openChat(ChatSessionModel chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Chats(
          title: chat.title,
          chatId: chat.id,
          isNew: false,
          offlineMode: widget.offlineMode,
        ),
      ),
    );
    if (mounted) _loadChats();
  }

  void _openDownloadScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DownloadPromptScreen(
          onSkip: () => Navigator.pop(context),
          onComplete: () => Navigator.pop(context),
          isForcedGate: false,
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    final colors = context.read<ThemeCubit>().state.colors;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Text('Delete Chat', style: TextStyle(color: colors.text)),
            content: Text(
              'Are you sure you want to delete this chat? This action cannot be undone.',
              style: TextStyle(color: colors.subtext),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: TextStyle(color: colors.subtext)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.buttonRadius,
                  ),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteChat(String chatId) async {
    final removedChats = _chats;
    setState(() {
      _chats = _chats.where((chat) => chat.id != chatId).toList();
    });

    try {
      final userId = await _localChatDao.getUserId();
      await _chatRepo.deleteChat(userId, chatId);
      await _loadChats();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chats = removedChats;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: colors.text,
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
              ),
              child: SvgPicture.asset(
                'assets/images/logo.svg',
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'AgentA',
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: Column(
        children: [
          OfflineModelBanner(onTap: () => _openDownloadScreen(context)),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colors.amber))
                : _chats.isNotEmpty
                ? Column(
                    children: [
                      if (_loadError != null) _buildStaleBanner(colors),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadChats,
                          color: colors.amber,
                          child: RepaintBoundary(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.base,
                                AppSpacing.base,
                                AppSpacing.base,
                                88,
                              ),
                              itemExtent: 108,
                              itemCount: _chats.length,
                              itemBuilder: (context, index) {
                                final chat = _chats[index];
                                return RepaintBoundary(
                                  child: Dismissible(
                                    key: ValueKey(chat.id),
                                    direction: DismissDirection.endToStart,
                                    confirmDismiss: (direction) async {
                                      return await _showDeleteConfirmation(
                                        context,
                                      );
                                    },
                                    onDismissed: (direction) {
                                      _deleteChat(chat.id);
                                    },
                                    background: _dismissBackground,
                                    child: _buildChatTile(chat, colors),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : _loadError != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colors.amber.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.error_outline_rounded,
                            color: colors.amber,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          _loadError!,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Please try again.',
                          style: TextStyle(color: colors.subtext, fontSize: 14),
                        ),
                        const SizedBox(height: AppSpacing.base),
                        ElevatedButton(
                          onPressed: _loadChats,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.amber,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.buttonRadius,
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colors.amber.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: colors.amber,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'No conversations yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Tap "New Chat" to start coaching',
                          style: TextStyle(color: colors.subtext, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        backgroundColor: colors.amber,
        foregroundColor: Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        icon: const Icon(Icons.edit_rounded, size: 20),
        label: const Text(
          'New Chat',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: widget.showBottomNav
          ? const BottomNav1(selectedIndex: 0)
          : null,
    );
  }

  /// Inline non-blocking banner shown above a populated list when a
  /// reload fails. Keeps the saved chats visible; never blocks scrolling
  /// and has no dismiss affordance beyond a successful retry.
  Widget _buildStaleBanner(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.amber.withValues(alpha: 0.15),
        border: Border(left: BorderSide(color: colors.amber, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.amber, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              "Couldn't refresh \u2014 showing your saved chats",
              style: TextStyle(
                color: colors.text.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: _loadChats,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(ChatSessionModel chat, ThemeColors colors) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
      color: colors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: () => _openChat(chat),
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  color: colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: colors.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chat.lastMessage.isEmpty
                          ? 'New conversation'
                          : chat.lastMessage,
                      style: TextStyle(color: colors.subtext, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _formatDate(chat.updatedAt),
                style: TextStyle(color: colors.subtext, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.day}/${date.month}';
  }
}
