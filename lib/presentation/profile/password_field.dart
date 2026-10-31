import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../shared/system_keyboard_text_field.dart';

/// Cycle 41 · F6 — the password field shell of record (spec §5.2/§5.3).
///
/// The existing well-decorated container plus the show/hide toggle:
/// independent obscured state per field (the caller owns it), a 48×48 touch
/// target, state-swapped tooltip + semantics label that states the ACTION
/// (CP-06), autofill hints (password managers fill correctly), and NO
/// maxLength — passwords are never truncated silently (GOV.UK technique).
/// The toggle never clears the field or moves focus; the icon swap animates
/// at [AppDurations.quick].
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.colors,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.prefixIcon,
    required this.obscured,
    required this.visibilityLabel,
    required this.onToggleVisibility,
    this.helperText,
    this.validator,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  final ThemeColors colors;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Field label — rendered above the field by the page and inside the
  /// decoration (the shipped pattern, retained).
  final String label;

  /// Prefix icon (lock for current, lock_outline for new — §5.2).
  final IconData prefixIcon;

  /// Current obscured state; the caller owns one flag per field.
  final bool obscured;

  /// CP-06 — the state-swapped semantics label + tooltip ("Show password" /
  /// "Hide password" / "Show new password" / "Hide new password").
  final String visibilityLabel;
  final VoidCallback onToggleVisibility;

  /// CP-05 on the new field ("At least 6 characters") — the app's recorded
  /// minimum stated up front (NN/g no-hidden-rulebook rule).
  final String? helperText;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.inputRadius,
        boxShadow: AppShadows.well,
      ),
      child: SystemKeyboardTextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscured,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        onChanged: onChanged,
        validator: validator,
        enabled: enabled,
        style: AppTypography.body.copyWith(color: colors.ink),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(prefixIcon, color: colors.subtext, size: 20),
          helperText: helperText,
          filled: true,
          fillColor: colors.base,
          suffixIcon: Semantics(
            // §11.2 — the state-swapped label states the ACTION (CP-06) for
            // assistive tech; the tooltip carries the same string.
            label: visibilityLabel,
            child: IconButton(
              onPressed: enabled ? onToggleVisibility : null,
              tooltip: visibilityLabel,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: AnimatedSwitcher(
                duration: AppDurations.quick,
                child: Icon(
                  obscured ? Icons.visibility : Icons.visibility_off,
                  key: ValueKey<bool>(obscured),
                  size: 22,
                  color: colors.subtext,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
