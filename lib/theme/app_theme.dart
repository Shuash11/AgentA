import 'package:flutter/material.dart';

/// Spacing scale — RETAINED from cycle-26 §4.3 (neumorphism spec §6: unchanged).
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

/// Radius scale — re-judged for neumorphic softness (spec §6):
/// chips 12 · buttons/inputs 16 · cards/tiles/FAB 20 · bubbles 24 ·
/// dialogs 28 · bottom sheets 32 (top corners).
class AppRadius {
  static const double sm = 12; // chips, badges
  static const double md = 16; // buttons, inputs, banners, snackbar
  static const double lg = 20; // cards, tiles, FAB, image bubbles
  static const double xl = 24; // chat bubbles + composer pill
  static const double xxl = 28; // dialogs
  static const double sheet = 32; // bottom sheets (top corners)

  /// Inline chips, small badges.
  static final BorderRadius chipRadius = BorderRadius.circular(sm);

  /// Buttons, inputs, banners, icon chips, snackbar.
  static final BorderRadius buttonRadius = BorderRadius.circular(md);
  static final BorderRadius inputRadius = BorderRadius.circular(md);
  static final BorderRadius bannerRadius = BorderRadius.circular(md);
  static final BorderRadius snackbarRadius = BorderRadius.circular(md);

  /// Cards, tiles, FAB, image bubbles.
  static final BorderRadius cardRadius = BorderRadius.circular(lg);
  static final BorderRadius tileRadius = BorderRadius.circular(lg);
  static final BorderRadius fabRadius = BorderRadius.circular(lg);

  /// Chat bubbles and the composer pill.
  static final BorderRadius bubbleRadius = BorderRadius.circular(xl);

  /// Dialogs.
  static final BorderRadius dialogRadius = BorderRadius.circular(xxl);

  /// Bottom sheets — top corners only.
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );

  /// Chat bubble tails — 6px (spec §6; user bottom-right, assistant bottom-left).
  static const BorderRadius assistantBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
    bottomLeft: Radius.circular(6),
    bottomRight: Radius.circular(xl),
  );
  static const BorderRadius userBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
    bottomLeft: Radius.circular(xl),
    bottomRight: Radius.circular(6),
  );
}

/// Motion — RETAINED (spec §6): 150/220/280 ms, easeOutCubic, no bounce;
/// loops honor `disableAnimationsOf`. Depth transitions (shadow offset/blur)
/// run at [quick] (150 ms).
class AppDurations {
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration entrance = Duration(milliseconds: 280);
  static const Curve standardCurve = Curves.easeOutCubic;
}

/// Color tokens — the flat neumorphic palette (spec §3; hexes normative).
///
/// ONE surface (`base`): scaffold, cards, tiles, sheets, inputs, bars,
/// bubbles. Depth comes from the shadow pair (§4), never tone. Semantic
/// container fills are dropped — status is icon + text in the semantic ink
/// on the neutral surface. AA is computed against `base` (spec §3 table).
class AppColors {
  // The ONE surface.
  static const Color base = Color(0xFFE0E5EC);

  // Ink.
  static const Color ink = Color(0xFF1A2433);
  static const Color subtext = Color(0xFF4A5568);
  static const Color disabledText = Color(0xFF8B95A5);

  // The ONE accent (fills/focus/progress — NEVER small text on base; accent
  // colored TEXT uses [accentInk]).
  static const Color accent = Color(0xFF3D5AFE);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color accentInk = Color(0xFF2A3990);

  // Semantic inks (status = icon + text, never surface decoration).
  static const Color successText = Color(0xFF146C2E);
  static const Color errorText = Color(0xFF8C1D1D);
  static const Color warningText = Color(0xFF7A5200);

  /// #000000 @ 54% — dialog/barrier scrim.
  static const Color scrim = Color(0x8A000000);

  // The dual-shadow pair (§4) — the ONLY shadow system (N5). Neutral,
  // derived from base; light source fixed top-left; never colored.
  static const Color shadowLight = Color(0xFFFFFFFF);
  static const Color shadowDark = Color(0xFFA3B1C6);

  /// M3 light scheme with the neumorphic tokens pinned onto the roles the
  /// app consumes; Material elevation is pinned to 0 app-wide (§4/§9 — the
  /// shadow pair is the only shadow system).
  static final ColorScheme lightColorScheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: base,
      ).copyWith(
        primary: accent,
        onPrimary: onAccent,
        surface: base,
        onSurface: ink,
        onSurfaceVariant: subtext,
        outline: shadowDark,
        outlineVariant: shadowDark,
        error: errorText,
        onError: onAccent,
        scrim: scrim,
      );
}

/// The ONLY shadow system (spec §4, N5) — copyable recipes verbatim.
/// Shadows animate offset/blur only, never color; the light source is fixed
/// top-left app-wide; blur/offset scale with element size (large surfaces 10,
/// controls 7, wells 5). Application points: the shared surface helpers
/// (P3) — never hand-rolled per call site.
class AppShadows {
  /// RAISED — cards, tiles, buttons at rest, banners, dialogs, sheets, bubbles.
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(-4, -4),
      blurRadius: 10,
    ),
    BoxShadow(
      color: AppColors.shadowDark,
      offset: Offset(4, 4),
      blurRadius: 10,
    ),
  ];

  /// PRESSED (inset) — buttons/tiles/tabs while pressed; selection wells.
  static const List<BoxShadow> pressed = [
    BoxShadow(
      color: AppColors.shadowDark,
      offset: Offset(-3, -3),
      blurRadius: 7,
    ),
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(3, 3),
      blurRadius: 7,
    ),
  ];

  /// INPUT WELL (inset, at rest) — text fields, search, code blocks.
  static const List<BoxShadow> well = [
    BoxShadow(
      color: AppColors.shadowDark,
      offset: Offset(-2, -2),
      blurRadius: 5,
    ),
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(2, 2),
      blurRadius: 5,
    ),
  ];

  /// FLAT (disabled) — no shadow; the element "sinks" by flattening.
  static const List<BoxShadow> flat = [];
}

/// Type scale — RETAINED VERBATIM from cycle-26 §4.1 (spec §6).
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
    titleSmall: labelSm.copyWith(color: AppColors.ink),
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: labelSm.copyWith(color: AppColors.subtext),
    labelLarge: button.copyWith(color: AppColors.ink),
    labelMedium: label.copyWith(color: AppColors.ink),
    labelSmall: micro.copyWith(color: AppColors.subtext),
  ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
}

/// The app theme — light only (spec §2a). Component defaults per the §5
/// state-visibility table. Material elevation is pinned to 0 everywhere:
/// the neumorphic shadow pair (§4) is the only shadow system, applied at
/// the widget layer by the shared surface helpers (P3).
class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: AppColors.lightColorScheme,
    scaffoldBackgroundColor: AppColors.base,
    fontFamily: 'Roboto',
    textTheme: AppTypography.textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.base,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
      titleTextStyle: AppTypography.subtitle.copyWith(color: AppColors.ink),
      // No bottom border/hairline — depth is the shadow system (spec §7).
    ),
    cardTheme: CardThemeData(
      color: AppColors.base,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.base,
      contentPadding: AppSpacing.inputPadding,
      // Resting field = the input well (AppShadows.well at the widget layer);
      // no border at rest — the label + well carry the affordance.
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.errorText, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.errorText, width: 1.5),
      ),
      labelStyle: AppTypography.label.copyWith(color: AppColors.subtext),
      floatingLabelStyle: AppTypography.label.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      hintStyle: AppTypography.labelSm.copyWith(color: AppColors.subtext),
      helperStyle: AppTypography.labelSm.copyWith(color: AppColors.subtext),
      errorStyle: AppTypography.labelSm.copyWith(color: AppColors.errorText),
      prefixIconColor: AppColors.subtext,
      suffixIconColor: AppColors.subtext,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.base
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
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.base),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.disabledText
              : AppColors.ink,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? AppColors.ink.withValues(alpha: 0.04)
              : null,
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
        textStyle: WidgetStatePropertyAll(AppTypography.button),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.disabledText
              : AppColors.accentInk,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
        textStyle: WidgetStatePropertyAll(AppTypography.body),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.ink),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      disabledElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.fabRadius),
      extendedTextStyle: AppTypography.button,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.base,
      elevation: 0,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.subtext,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.snackbarRadius),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.base,
      modalBackgroundColor: AppColors.base,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: AppColors.shadowDark,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.base,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialogRadius),
      titleTextStyle: AppTypography.title.copyWith(color: AppColors.ink),
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.subtext),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.base,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.shadowDark,
      thickness: 1,
    ),
  );
}

/// Flat neumorphic palette consumed by screens via `context.select`
/// (spec §3/§9). Light-only state (spec §2a).
class ThemeColors {
  const ThemeColors();

  Color get base => AppColors.base;
  Color get ink => AppColors.ink;
  Color get subtext => AppColors.subtext;
  Color get disabledText => AppColors.disabledText;
  Color get accent => AppColors.accent;
  Color get onAccent => AppColors.onAccent;
  Color get accentInk => AppColors.accentInk;
  Color get successText => AppColors.successText;
  Color get errorText => AppColors.errorText;
  Color get warningText => AppColors.warningText;
  Color get scrim => AppColors.scrim;

  Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }
}
