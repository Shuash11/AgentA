import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../data/models/chat_message_model.dart';
import '../../../theme/app_theme.dart';
import 'animated_bubble.dart';
import 'chat_activity_state.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';

class ChatTimelineView extends StatelessWidget {
  final ValueListenable<List<ChatMessageModel>> messagesListenable;
  final ValueListenable<ChatActivityState> activityListenable;
  final ScrollController scrollController;
  final ThemeColors colors;
  final bool animateEmpty;
  final bool isImageGeneration;

  const ChatTimelineView({
    super.key,
    required this.messagesListenable,
    required this.activityListenable,
    required this.scrollController,
    required this.colors,
    required this.animateEmpty,
    required this.isImageGeneration,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatActivityState>(
      valueListenable: activityListenable,
      builder: (context, activity, _) {
        if (activity.isLoadingMessages) {
          return _LoadingPlaceholder(colors: colors);
        }

        return ValueListenableBuilder<List<ChatMessageModel>>(
          valueListenable: messagesListenable,
          builder: (context, messages, _) {
            if (messages.isEmpty && !activity.isTyping) {
              return _EmptyChat(colors: colors, animate: animateEmpty);
            }

            return ListView.builder(
              controller: scrollController,
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: messages.length + (activity.isTyping ? 1 : 0),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemBuilder: (context, index) {
                if (index == messages.length && activity.isTyping) {
                  return TypingIndicator(
                    key: const ValueKey('typing_indicator'),
                    colors: colors,
                    isImageGeneration: isImageGeneration,
                    isInitializing: activity.isInitializingModel,
                  );
                }

                final msg = messages[index];
                final isStreamingMessage = activity.isTyping &&
                    index == messages.length - 1 &&
                    !msg.isUser;

                return AnimatedBubble(
                  key: ValueKey(msg.id),
                  isUser: msg.isUser,
                  index: index,
                  child: MessageBubble(
                    message: msg,
                    colors: colors,
                    isStreaming: isStreamingMessage,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  final ThemeColors colors;

  const _LoadingPlaceholder({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              color: colors.amber,
              backgroundColor: colors.border,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading messages...',
            style: TextStyle(color: colors.subtext, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final ThemeColors colors;
  final bool animate;

  const _EmptyChat({
    required this.colors,
    required this.animate,
  });

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.withOpacity(colors.amber, 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.bolt_rounded, color: colors.amber, size: 44),
        ),
        const SizedBox(height: 20),
        Text(
          'Start the conversation',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask AgentA anything about your career',
          style: TextStyle(color: colors.subtext, fontSize: 13),
        ),
      ],
    );

    if (!animate) return Center(child: child);

    return Center(
      child: TweenAnimationBuilder<double>(
        key: ValueKey('empty_chat_$animate'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (_, val, child) => Opacity(
          opacity: val,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - val)),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}
