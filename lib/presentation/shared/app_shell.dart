import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/theme/theme_cubit.dart';
import '../../cubit/connectivity/connectivity_cubit.dart';
import '../dashboard/dashboard.dart';
import '../profile/profilepage.dart';
import 'bottomnavbar.dart';

class AppShell extends StatefulWidget {
  final bool offlineMode;
  final int initialIndex;

  const AppShell({super.key, this.offlineMode = false, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.select((ThemeCubit c) => c.state.colors);
    final isOnline = context.select((ConnectivityCubit c) => c.state.isOnline);
    final isOffline = !isOnline;

    return Scaffold(
      backgroundColor: colors.base,
      body: RepaintBoundary(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            Dashboard(
              offlineMode: isOffline,
              showBottomNav: false,
              showBackButton: false,
            ),
            const ProfilePage(showBottomNav: false),
          ],
        ),
      ),
      bottomNavigationBar: BottomNav1(
        selectedIndex: _selectedIndex,
        onTabSelected: (index) {
          if (index == _selectedIndex) return;
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
