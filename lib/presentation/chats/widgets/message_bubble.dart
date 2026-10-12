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
        color: colors.amber.withValues(alpha: 0.9),
        borderRadius: AppRadius.userBubbleRadius,
        boxShadow: [
          BoxShadow(
            color: colors.withOpacity(colors.amber, 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );
    }
    return BoxDecoration(
      color: colors.card,
      borderRadius: AppRadius.assistantBubbleRadius,
      border: Border.all(color: colors.border, width: 0.5),
      boxShadow: [
        BoxShadow(
          color: colors.withOpacity(Colors.black, 0.06),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  TextStyle _getTextStyle(bool isUser) {
    return TextStyle(
      color: isUser ? Colors.black : colors.text,
      fontSize: 14.5,
      height: 1.45,
    );
  }

  static final MarkdownStyleSheet _cachedMarkdownStyleSheetUser =
      MarkdownStyleSheet(
        p: const TextStyle(color: Colors.black, fontSize: 14.5, height: 1.45),
        code: const TextStyle(
          color: Colors.black,
          fontSize: 13.5,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        blockquote: const TextStyle(
          color: Color(0xFF757575),
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFFFB300), width: 3)),
        ),
        listBullet: const TextStyle(color: Colors.black),
        h1: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        h4: const TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        h5: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        h6: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        a: const TextStyle(
          color: Colors.black87,
          decoration: TextDecoration.underline,
        ),
        strong: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
        em: const TextStyle(color: Colors.black, fontStyle: FontStyle.italic),
      );

  static final MarkdownStyleSheet _cachedMarkdownStyleSheetAssistant =
      MarkdownStyleSheet(
        p: const TextStyle(color: Colors.black, fontSize: 14.5, height: 1.45),
        code: const TextStyle(
          color: Colors.black,
          fontSize: 13.5,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        blockquote: const TextStyle(
          color: Color(0xFF757575),
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFFFB300), width: 3)),
        ),
        listBullet: const TextStyle(color: Colors.black),
        h1: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        h4: const TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        h5: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        h6: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        a: const TextStyle(
          color: Colors.amber,
          decoration: TextDecoration.underline,
        ),
        strong: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
        em: const TextStyle(color: Colors.black, fontStyle: FontStyle.italic),
      );

  MarkdownStyleSheet _getMarkdownStyleSheet(bool isUser) {
    if (isUser) return _cachedMarkdownStyleSheetUser;

    return _cachedMarkdownStyleSheetAssistant.copyWith(
      p: TextStyle(color: colors.text, fontSize: 14.5, height: 1.45),
      code: TextStyle(
        color: colors.text,
        fontSize: 13.5,
        fontFamily: 'monospace',
      ),
      listBullet: TextStyle(color: colors.text),
      h1: TextStyle(
        color: colors.text,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      h2: TextStyle(
        color: colors.text,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      h3: TextStyle(
        color: colors.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      h4: TextStyle(
        color: colors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      h5: TextStyle(
        color: colors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      h6: TextStyle(
        color: colors.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      a: TextStyle(color: colors.amber, decoration: TextDecoration.underline),
      strong: TextStyle(color: colors.text, fontWeight: FontWeight.bold),
      em: TextStyle(color: colors.text, fontStyle: FontStyle.italic),
    );
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
    final copyColor = isUser
        ? Colors.black.withValues(alpha: 0.65)
        : colors.subtext;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              tooltip: 'Copy message',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, size: 16, color: copyColor),
              onPressed: () => _copyMessage(context),
            ),
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
