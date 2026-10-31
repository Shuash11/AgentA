import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Cycle 41 · F2 — the inline cancel-recovery card for the device-credential
/// step (designs/cycle-41-change-password-redesign.md §7.1).
///
/// Replaces the shipped terminal dead-end (the retired device-cancel abort
/// copy — see spec §10.3): a canceled system prompt is user intent, not an
/// error condition, so the card explains what happened, that nothing was
/// saved yet, and offers Try again (the caller re-runs ONLY the failed step)
/// / Back. Inline content — never a dialog; the form and its values stay
/// visible above it.
///
/// All styling comes from the app's design system (§2): `base` surface,
/// `raised` shadow, card radius 20, status = icon + text in semantic inks —
/// never a colored panel.
class DeviceRetryCard extends StatelessWidget {
  const DeviceRetryCard({
    super.key,
    required this.colors,
    required this.isBusy,
    required this.showSpinner,
    required this.onTryAgain,
    required this.onBack,
  });

  /// The page's resolved theme colors (the flat neumorphic palette).
  final ThemeColors colors;

  /// True while a submit or retry attempt is in flight — both actions are
  /// disabled (§9: buttons disabled during the retry's prompt).
  final bool isBusy;

  /// True only while a Try-again attempt is in flight — "Try again" shows
  /// the button spinner (§9 loading column).
  final bool showSpinner;

  /// Re-runs only the failed device step (never the whole chain, never a
  /// consumed send — the no-waste rule).
  final VoidCallback onTryAgain;

  /// Returns to the form state with both fields intact and every chain
  /// state cleared.
  final VoidCallback onBack;

  /// CP-15 — the retry-card title.
  static const String title = "Your phone's screen lock didn't confirm";

  /// CP-16 — the retry-card body.
  static const String body =
      'Your password was not changed. Nothing has been saved yet. '
      'Try again to continue.';

  /// CP-17 — the retry-card actions.
  static const String tryAgainLabel = 'Try again';
  static const String backLabel = 'Back';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Announced as a unit when it appears; the title is the semantic
      // header (§11.2).
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: colors.base,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadows.raised,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phonelink_lock, size: 24, color: colors.warningText),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppTypography.subtitle.copyWith(color: colors.ink),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              style: AppTypography.body.copyWith(color: colors.subtext),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.buttonRadius,
                      boxShadow: isBusy ? AppShadows.flat : AppShadows.raised,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isBusy ? null : onTryAgain,
                        child: showSpinner
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onAccent,
                                ),
                              )
                            : const Text(tryAgainLabel),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // The theme's TextButton style renders accentInk when
                // enabled and disabledText while [isBusy] — no hardcoded
                // color here so the disabled state stays visible (§9).
                TextButton(
                  onPressed: isBusy ? null : onBack,
                  child: Text(backLabel, style: AppTypography.body),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
