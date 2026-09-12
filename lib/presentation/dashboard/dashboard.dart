import 'dart:async';

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
    if (_chats.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final userId = await _localChatDao.getUserId();
      final chats = await _chatRepo.getChatsForUser(userId);
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        
        setState(() => _isLoading = false);
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

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    final colors = context.read<ThemeCubit>().state.colors;
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
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
    ) ?? false;
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
          const OfflineModelBanner(),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: colors.amber),
                  )
                : _chats.isEmpty
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
                              child: Icon(Icons.chat_bubble_outline_rounded,
                                  color: colors.amber, size: 48),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text('No conversations yet',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w600, color: colors.text)),
                            const SizedBox(height: AppSpacing.sm),
                            Text('Tap "New Chat" to start coaching',
                                style: TextStyle(color: colors.subtext, fontSize: 14)),
                          ],
                        ),
                      )
: RefreshIndicator(
                        onRefresh: _loadChats,
                        color: colors.amber,
                        child: RepaintBoundary(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.base, AppSpacing.base, 88),
                            itemExtent: 108,
                            itemCount: _chats.length,
                            itemBuilder: (context, index) {
                              final chat = _chats[index];
                              return RepaintBoundary(
                                child: Dismissible(
                                key: ValueKey(chat.id),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (direction) async {
                                  return await _showDeleteConfirmation(context);
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
      bottomNavigationBar:
          widget.showBottomNav ? const BottomNav1(selectedIndex: 0) : null,
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
                child: Icon(Icons.chat_bubble_rounded, color: colors.amber, size: 24),
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
                      chat.lastMessage.isEmpty ? 'New conversation' : chat.lastMessage,
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
