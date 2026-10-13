import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../shared/system_keyboard_text_field.dart';

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final ThemeColors colors;
  final bool isTyping;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onStop,
    required this.colors,
    this.isTyping = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<bool> _hasTextNotifier = ValueNotifier<bool>(false);

  static const _borderRadius = BorderRadius.all(Radius.circular(20));
  static const _inputDecoration = InputDecoration(
    hintText: 'Ask AgentA...',
    filled: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: _borderRadius,
      borderSide: BorderSide(color: Colors.transparent),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: _borderRadius,
      borderSide: BorderSide(color: Colors.transparent),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: _borderRadius,
      borderSide: BorderSide(color: Colors.transparent),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: _borderRadius,
      borderSide: BorderSide(color: Colors.transparent),
    ),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncHasText);
    _syncHasText();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncHasText);
      widget.controller.addListener(_syncHasText);
      _syncHasText();
    }
  }

  void _syncHasText() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (_hasTextNotifier.value != hasText) {
      _hasTextNotifier.value = hasText;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHasText);
    _hasTextNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          10,
          AppSpacing.base,
          12,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SystemKeyboardTextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: colors.text, fontSize: 14.5),
                  decoration: _inputDecoration.copyWith(
                    hintStyle: TextStyle(color: colors.subtext, fontSize: 14.5),
                    fillColor: colors.input,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            ValueListenableBuilder<bool>(
              valueListenable: _hasTextNotifier,
              builder: (context, hasText, _) {
                return _SendButton(
                  isTyping: widget.isTyping,
                  hasText: hasText,
                  colors: colors,
                  onSend: widget.onSend,
                  onStop: widget.onStop,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool isTyping;
  final bool hasText;
  final ThemeColors colors;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  const _SendButton({
    required this.isTyping,
    required this.hasText,
    required this.colors,
    required this.onSend,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final bool shouldShow = isTyping || hasText;
    final color = isTyping
        ? colors.error
        : shouldShow
        ? colors.amber
        : colors.input;
    final iconColor = shouldShow ? Colors.black : colors.subtext;

    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: shouldShow ? (isTyping ? onStop : onSend) : null,
          borderRadius: BorderRadius.circular(16),
          child: Icon(
            isTyping ? Icons.stop_rounded : Icons.send_rounded,
            color: iconColor,
            size: 20,
          ),
        ),
      ),
    );
  }
}
