import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/app_theme.dart';

/// Light-only theme state (spec §2). The cubit shell is retained so every
/// screen keeps consuming `state.colors` via `context.select`.
class ThemeState {
  final ThemeData themeData;
  final ThemeColors colors;

  const ThemeState({required this.themeData, required this.colors});

  factory ThemeState.light() =>
      ThemeState(themeData: AppTheme.lightTheme, colors: const ThemeColors());
}

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(ThemeState.light());
}
