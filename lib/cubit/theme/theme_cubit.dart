import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/app_theme.dart';

class ThemeState {
  final bool isDarkMode;
  final ThemeData themeData;
  final ThemeColors colors;

  ThemeState({
    required this.isDarkMode,
    required this.themeData,
    required this.colors,
  });

  factory ThemeState.dark() => ThemeState(
    isDarkMode: true,
    themeData: AppTheme.darkTheme,
    colors: const ThemeColors(true),
  );

  factory ThemeState.light() => ThemeState(
    isDarkMode: false,
    themeData: AppTheme.lightTheme,
    colors: const ThemeColors(false),
  );

  ThemeState copyWith({
    bool? isDarkMode,
    ThemeData? themeData,
    ThemeColors? colors,
  }) {
    return ThemeState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      themeData: themeData ?? this.themeData,
      colors: colors ?? this.colors,
    );
  }
}

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(ThemeState.dark());

  void toggleDarkMode(bool value) {
    if (state.isDarkMode != value) {
      if (value) {
        emit(ThemeState.dark());
      } else {
        emit(ThemeState.light());
      }
    }
  }

  void setDarkMode(bool isDark) {
    if (state.isDarkMode != isDark) {
      if (isDark) {
        emit(ThemeState.dark());
      } else {
        emit(ThemeState.light());
      }
    }
  }
}
