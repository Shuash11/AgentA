import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../theme/app_theme.dart';

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppDurations.quick,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: isSelected
              ? BoxDecoration(
                  color: colors.accentContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                color: isSelected ? colors.onAccentContainer : colors.subtext,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: AppTypography.micro.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? colors.onAccentContainer : colors.subtext,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BottomNav1 extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int>? onTabSelected;

  const BottomNav1({
    super.key,
    required this.selectedIndex,
    this.onTabSelected,
  });

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: "Home",
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: "Profile",
    ),
  ];

  void _onTap(int index) {
    if (index == selectedIndex) return;
    onTabSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppSpacing.sm + 4,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border, width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            _items.length,
            (index) => _NavButton(
              item: _items[index],
              isSelected: selectedIndex == index,
              colors: colors,
              onTap: () => _onTap(index),
            ),
          ),
        ),
      ),
    );
  }
}
