import 'package:flutter/material.dart';

/// Spacing scale (spec §4.3): xs 4 / sm 8 / md 12 / base 16 / lg 20 / xl 24 / xxl 32.
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

  /// Text-field content padding (spec §4.3/§5.4: h16/v14).
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );

  /// Chat composer pill content padding (spec §4.3: h16/v12).
  static const EdgeInsets chatInputPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );

  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: base,
    vertical: md,
  );
}

/// Radius scale (spec §4.2) — differentiated by element role.
class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Inline chips, small badges.
  static final BorderRadius chipRadius = BorderRadius.circular(sm);

  /// Buttons, inputs, banners, icon chips, snackbar.
  static final BorderRadius buttonRadius = BorderRadius.circular(md);
  static final BorderRadius inputRadius = BorderRadius.circular(md);
  static final BorderRadius bannerRadius = BorderRadius.circular(md);
  static final BorderRadius snackbarRadius = BorderRadius.circular(md);

  /// Cards, tiles, image bubbles, FAB.
  static final BorderRadius cardRadius = BorderRadius.circular(lg);
  static final BorderRadius tileRadius = BorderRadius.circular(lg);
  static final BorderRadius fabRadius = BorderRadius.circular(lg);

  /// Chat bubbles and dialogs.
  static final BorderRadius bubbleRadius = BorderRadius.circular(xl);
  static final BorderRadius dialogRadius = BorderRadius.circular(xl);

  /// Bottom sheets — top corners only.
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(xxl),
  );

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

/// Motion (spec §4.5) — kept: fade/slide only, no bounce/elastic.
class AppDurations {
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration entrance = Duration(milliseconds: 280);
  static const Curve standardCurve = Curves.easeOutCubic;
}

/// Color tokens — light palette only (spec §3). Hexes are normative.
class AppColors {
  // Neutrals (§3.1).
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color input = Color(0xFFF1F3F5);
  static const Color border = Color(0xFFE2E5EA);
  static const Color inputBorder = Color(0xFFD5DAE0);
  static const Color text = Color(0xFF111827);
  static const Color subtext = Color(0xFF5B6472);
  static const Color disabledText = Color(0xFF9AA1AA);

  /// #000000 @ 54% — dialog barriers.
  static const Color scrim = Color(0x8A000000);

  // Accent (§3.2) — the ONE accent.
  static const Color accent = Color(0xFF3D5AFE);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color accentContainer = Color(0xFFE8ECFF);
  static const Color onAccentContainer = Color(0xFF2A3990);

  // Semantic (§3.3) — status only, never decoration.
  static const Color success = Color(0xFF1B7F3B);
  static const Color successContainer = Color(0xFFE6F4EA);
  static const Color onSuccessContainer = Color(0xFF146C2E);
  static const Color error = Color(0xFFC62828);
  static const Color errorContainer = Color(0xFFFCE8E8);
  static const Color onErrorContainer = Color(0xFF8C1D1D);
  static const Color warning = Color(0xFF9A6700);
  static const Color warningContainer = Color(0xFFFFF4D6);
  static const Color onWarningContainer = Color(0xFF7A5200);

  /// M3 light scheme with the normative §3 hexes pinned onto the roles
  /// the app actually consumes (one accent; derived roles stay M3).
  static final ColorScheme lightColorScheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: surface,
      ).copyWith(
        primary: accent,
        onPrimary: onAccent,
        primaryContainer: accentContainer,
        onPrimaryContainer: onAccentContainer,
        onSurface: text,
        onSurfaceVariant: subtext,
        outline: inputBorder,
        outlineVariant: border,
        error: error,
        onError: onAccent,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
      );
}

/// Type scale (spec §4.1) — Roboto retained; hierarchy from size/weight only.
class AppTypography {
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const TextStyle bodyChat = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const TextStyle labelSm = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Button label (spec §5.1/§5.2): `body` at w600.
  static final TextStyle button = body.copyWith(fontWeight: FontWeight.w600);

  /// M3 slot mapping consumed as the app `TextTheme` (spec §4.1).
  static TextTheme get textTheme => TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: display,
    headlineMedium: display,
    headlineSmall: title,
    titleLarge: title,
    titleMedium: subtitle,
    titleSmall: labelSm.copyWith(color: AppColors.text),
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: labelSm.copyWith(color: AppColors.subtext),
    labelLarge: button.copyWith(color: AppColors.text),
    labelMedium: label.copyWith(color: AppColors.text),
    labelSmall: micro.copyWith(color: AppColors.subtext),
  ).apply(bodyColor: AppColors.text, displayColor: AppColors.text);
}

/// The app theme — light only (spec §2). Component defaults per §5.
class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: AppColors.lightColorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: AppTypography.textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: AppColors.text, size: 20),
      titleTextStyle: AppTypography.subtitle.copyWith(color: AppColors.text),
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.input,
      contentPadding: AppSpacing.inputPadding,
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      labelStyle: AppTypography.label.copyWith(color: AppColors.subtext),
      floatingLabelStyle: AppTypography.label.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      hintStyle: AppTypography.labelSm.copyWith(color: AppColors.subtext),
      helperStyle: AppTypography.labelSm.copyWith(color: AppColors.subtext),
      errorStyle: AppTypography.labelSm.copyWith(color: AppColors.error),
      prefixIconColor: AppColors.subtext,
      suffixIconColor: AppColors.subtext,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.input
              : AppColors.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.disabledText
              : AppColors.onAccent,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? AppColors.onAccent.withValues(alpha: 0.11)
              : null,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
        textStyle: WidgetStatePropertyAll(AppTypography.button),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.disabledText
              : AppColors.text,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? AppColors.text.withValues(alpha: 0.04)
              : null,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? AppColors.border
                : AppColors.inputBorder,
          ),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
        textStyle: WidgetStatePropertyAll(AppTypography.button),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.disabledText
              : AppColors.accent,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
        textStyle: WidgetStatePropertyAll(AppTypography.body),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.text),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.fabRadius),
      extendedTextStyle: AppTypography.button,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      selectedItemColor: AppColors.onAccentContainer,
      unselectedItemColor: AppColors.subtext,
      selectedLabelStyle: AppTypography.micro.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypography.micro,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.snackbarRadius),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: AppColors.border,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialogRadius),
      titleTextStyle: AppTypography.title.copyWith(color: AppColors.text),
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.subtext),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.input,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  );
}

/// Flat light palette consumed by screens via `context.select` (spec §2/§3).
class ThemeColors {
  const ThemeColors();

  Color get background => AppColors.background;
  Color get surface => AppColors.surface;
  Color get card => AppColors.card;
  Color get input => AppColors.input;
  Color get border => AppColors.border;
  Color get inputBorder => AppColors.inputBorder;
  Color get text => AppColors.text;
  Color get subtext => AppColors.subtext;
  Color get disabledText => AppColors.disabledText;
  Color get scrim => AppColors.scrim;

  Color get accent => AppColors.accent;
  Color get onAccent => AppColors.onAccent;
  Color get accentContainer => AppColors.accentContainer;
  Color get onAccentContainer => AppColors.onAccentContainer;

  Color get success => AppColors.success;
  Color get successContainer => AppColors.successContainer;
  Color get onSuccessContainer => AppColors.onSuccessContainer;
  Color get error => AppColors.error;
  Color get errorContainer => AppColors.errorContainer;
  Color get onErrorContainer => AppColors.onErrorContainer;
  Color get warning => AppColors.warning;
  Color get warningContainer => AppColors.warningContainer;
  Color get onWarningContainer => AppColors.onWarningContainer;

  Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }
}
