import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../data/models/chat_message_model.dart';
import '../../../theme/app_theme.dart';
import 'auto_retry_image.dart';
import 'image_bubble.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final ThemeColors colors;
  final bool isStreaming;
  final Future<void> Function(String messageId)? onImageFallback;
  final bool fallbackAvailable;
  static const double _maxBubbleWidthFactor = 0.75;

  const MessageBubble({
    super.key,
    required this.message,
    required this.colors,
    this.isStreaming = false,
    this.onImageFallback,
    this.fallbackAvailable = false,
  });

  BoxDecoration _buildDecoration(bool isUser, bool isImageMessage) {
    if (isUser) {
      return BoxDecoration(
        color: colors.accent,
        borderRadius: AppRadius.userBubbleRadius,
      );
    }
    return BoxDecoration(
      color: colors.card,
      borderRadius: AppRadius.assistantBubbleRadius,
      border: Border.all(color: colors.border),
    );
  }

  TextStyle _getTextStyle(bool isUser) {
    return AppTypography.bodyChat.copyWith(
      color: isUser ? colors.onAccent : colors.text,
    );
  }

  static final MarkdownStyleSheet _cachedMarkdownStyleSheetUser =
      _buildMarkdownStyleSheet(
        ink: AppColors.onAccent,
        link: AppColors.onAccent,
        blockquote: AppColors.onAccent,
      );

  static final MarkdownStyleSheet _cachedMarkdownStyleSheetAssistant =
      _buildMarkdownStyleSheet(
        ink: AppColors.text,
        link: AppColors.accent,
        blockquote: AppColors.subtext,
      );

  /// Markdown styling per §5.16. Code blocks keep the light `input` surface in
  /// both bubbles (ink text); the user bubble renders all body/heading text in
  /// `onAccent` on the accent fill, the assistant bubble in ink with `subtext`
  /// blockquotes and accent links.
  static MarkdownStyleSheet _buildMarkdownStyleSheet({
    required Color ink,
    required Color link,
    required Color blockquote,
  }) {
    return MarkdownStyleSheet(
      p: AppTypography.bodyChat.copyWith(color: ink),
      code: const TextStyle(
        color: AppColors.text,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: AppColors.border),
      ),
      blockquote: AppTypography.body.copyWith(
        color: blockquote,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border, width: 2)),
      ),
      listBullet: TextStyle(color: ink),
      h1: AppTypography.title.copyWith(color: ink),
      h2: AppTypography.subtitle.copyWith(color: ink),
      h3: AppTypography.body.copyWith(color: ink, fontWeight: FontWeight.w700),
      h4: AppTypography.body.copyWith(color: ink, fontWeight: FontWeight.w600),
      h5: AppTypography.label.copyWith(color: ink, fontWeight: FontWeight.w600),
      h6: AppTypography.labelSm.copyWith(
        color: ink,
        fontWeight: FontWeight.w600,
      ),
      a: TextStyle(color: link, decoration: TextDecoration.underline),
      strong: TextStyle(color: ink, fontWeight: FontWeight.bold),
      em: TextStyle(color: ink, fontStyle: FontStyle.italic),
    );
  }

  MarkdownStyleSheet _getMarkdownStyleSheet(bool isUser) {
    if (isUser) return _cachedMarkdownStyleSheetUser;

    return _cachedMarkdownStyleSheetAssistant;
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isImageMessage = !isUser && _isImageUrl(message.text);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth * _maxBubbleWidthFactor;

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: isImageMessage
                ? const EdgeInsets.all(8)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: _buildDecoration(isUser, isImageMessage),
            child: isImageMessage
                ? _buildImageMessage(maxWidth - 16)
                : _buildCopyableTextContent(context, isUser),
          ),
        );
      },
    );
  }

  Widget _buildCopyableTextContent(BuildContext context, bool isUser) {
    final content = _buildTextContent(isUser);
    final copyColor = isUser ? colors.onAccent : colors.subtext;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Copy message',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.copy_rounded, size: 16, color: copyColor),
            onPressed: () => _copyMessage(context),
          ),
        ),
      ],
    );
  }

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    unawaited(HapticFeedback.lightImpact());
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  Widget _buildTextContent(bool isUser) {
    final text = message.text;
    if (isStreaming || !message.hasMarkdown) {
      return Text(text, style: _getTextStyle(isUser));
    }
    return MarkdownBody(
      data: text,
      shrinkWrap: true,
      styleSheet: _getMarkdownStyleSheet(isUser),
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
  }

  bool _isImageUrl(String text) {
    final trimmed = text.trim();
    if (isLocalImagePath(trimmed)) return true;
    if (trimmed.startsWith('http') &&
        trimmed.contains('image.pollinations.ai')) {
      return true;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }

    final normalizedPath = uri.path.toLowerCase();
    const imageExtensions = ['.png', '.jpg', '.jpeg', '.webp', '.gif'];

    return imageExtensions.any(normalizedPath.endsWith);
  }

  Widget _buildImageMessage(double bubbleWidth) {
    final imageUrl = message.text.trim();

    return ImageBubbleContent(
      imageUrl: imageUrl,
      colors: colors,
      width: bubbleWidth,
      fallbackAvailable: fallbackAvailable && !isLocalImagePath(imageUrl),
      onFallbackRequested: onImageFallback == null
          ? null
          : () => onImageFallback!(message.id),
    );
  }
}
