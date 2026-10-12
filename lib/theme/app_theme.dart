import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  static const EdgeInsets pagePadding = EdgeInsets.all(base);
  static const EdgeInsets cardPadding = EdgeInsets.all(base);
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: base,
    vertical: md,
  );
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  static final BorderRadius buttonRadius = BorderRadius.circular(md);
  static final BorderRadius inputRadius = BorderRadius.circular(md);
  static final BorderRadius cardRadius = BorderRadius.circular(md);
  static final BorderRadius bubbleRadius = BorderRadius.circular(xl);
  static const BorderRadius assistantBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
    bottomLeft: Radius.circular(4),
    bottomRight: Radius.circular(xl),
  );
  static const BorderRadius userBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
    bottomLeft: Radius.circular(xl),
    bottomRight: Radius.circular(4),
  );
}

class AppDurations {
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration entrance = Duration(milliseconds: 280);
  static const Curve standardCurve = Curves.easeOutCubic;
}

class AppColors {
  static const Color amber = Color(0xFFFFC107);
  static const Color amberDark = Color(0xFFFFA000);
  static const Color amberLight = Color(0xFFFFE082);

  static const Color darkBg = Color(0xFF0D0D0D);
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkCardAlt = Color(0xFF1C1C1C);
  static const Color darkInput = Color(0xFF2A2A2A);

  static const Color lightBg = Color(0xFFF5F5F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightInput = Color(0xFFF5F5F5);

  static const Color textDark = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF000000);
  static const Color subDark = Color(0x8AFFFFFF);
  static const Color subLight = Color(0x8A000000);

  static const Color borderDark = Color(0x1AFFFFFF);
  static const Color borderLight = Color(0x1A000000);

  static const Color success = Color(0xFF4CAF50);
  static const Color successDark = Color(0xFF2E7D32);
  static const Color error = Color(0xFFF44336);
  static const Color errorDark = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningDark = Color(0xFFF57C00);
  static const Color info = Color(0xFF2196F3);

  static ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: amber,
    brightness: Brightness.dark,
    surface: darkSurface,
  );

  static ColorScheme lightColorScheme = ColorScheme.fromSeed(
    seedColor: amber,
    brightness: Brightness.light,
    surface: lightSurface,
  );
}

class AppTheme {
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,
    colorScheme: AppColors.darkColorScheme,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      elevation: 0,
      foregroundColor: AppColors.textDark,
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkInput,
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.amber,
        side: const BorderSide(color: AppColors.amber),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.amber,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.textDark),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.amber,
      foregroundColor: Colors.black,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor: AppColors.amber,
      unselectedItemColor: AppColors.subDark,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkCard,
      contentTextStyle: const TextStyle(color: AppColors.textDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderDark,
      thickness: 1,
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    colorScheme: AppColors.lightColorScheme,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      elevation: 0,
      foregroundColor: AppColors.textLight,
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightInput,
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.amberDark,
        side: const BorderSide(color: AppColors.amber),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.amberDark,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.textLight),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.amber,
      foregroundColor: Colors.black,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.lightSurface,
      selectedItemColor: AppColors.amberDark,
      unselectedItemColor: AppColors.subLight,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.lightCard,
      contentTextStyle: const TextStyle(color: AppColors.textLight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderLight,
      thickness: 1,
    ),
  );
}

class ThemeColors {
  final bool isDark;

  const ThemeColors(this.isDark);

  Color get background => isDark ? AppColors.darkBg : AppColors.lightBg;
  Color get surface => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get card => isDark ? AppColors.darkCard : AppColors.lightCard;
  Color get input => isDark ? AppColors.darkInput : AppColors.lightInput;
  Color get text => isDark ? AppColors.textDark : AppColors.textLight;
  Color get subtext => isDark ? AppColors.subDark : AppColors.subLight;
  Color get border => isDark ? AppColors.borderDark : AppColors.borderLight;
  Color get amber => AppColors.amber;
  Color get success => isDark ? AppColors.success : AppColors.successDark;
  Color get error => isDark ? AppColors.error : AppColors.errorDark;
  Color get warning => isDark ? AppColors.warning : AppColors.warningDark;

  Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }
}
