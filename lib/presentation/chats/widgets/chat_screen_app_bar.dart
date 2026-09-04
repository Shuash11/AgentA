import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class ChatScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String modelName;
  final ThemeColors colors;
  final VoidCallback onBack;
  final VoidCallback onModelPickerTap;

  const ChatScreenAppBar({
    super.key,
    required this.title,
    required this.modelName,
    required this.colors,
    required this.onBack,
    required this.onModelPickerTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        color: colors.text,
        onPressed: onBack,
      ),
      title: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            modelName,
            style: TextStyle(color: colors.amber, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          color: colors.text,
          onPressed: onModelPickerTap,
        ),
      ],
      backgroundColor: colors.surface,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: colors.border),
      ),
    );
  }
}
