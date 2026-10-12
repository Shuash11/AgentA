import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubit/update/update_cubit.dart';
import 'update_available_dialog.dart';

/// App-level host for [UpdateAvailableDialog], mounted via `MaterialApp
/// builder:` so the dialog overlays EVERY screen (login, model-download gate,
/// shell).
///
/// Shows the dialog per the Adviser show rules:
///  - status == available AND the shown version was not dismissed, OR
///  - status == forced.
///
/// A duplicate-dialog guard (a flag while showing) prevents stacking; after
/// the dialog closes, a newer version re-triggers it automatically. Any close
/// path of a non-forced dialog (Update, Later, barrier tap) dismisses the
/// shown version; forced dialogs are non-dismissible and never close by
/// design ([UpdateCubit.dismissUntilNextVersion] refuses forced updates).
class UpdateDialogHost extends StatefulWidget {
  final Widget child;

  /// Root navigator key. The host sits ABOVE the navigator (MaterialApp
  /// builder), so its own context cannot resolve a Navigator — dialog routes
  /// are pushed through this key directly instead. Assign it to the app's
  /// `MaterialApp.navigatorKey` (see main.dart).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const UpdateDialogHost({super.key, required this.child});

  @override
  State<UpdateDialogHost> createState() => _UpdateDialogHostState();
}

class _UpdateDialogHostState extends State<UpdateDialogHost> {
  bool _isShowing = false;

  @override
  void initState() {
    super.initState();
    // Seed: the cubit may already hold a showable state when the host mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showIfDue());
  }

  @override
  Widget build(BuildContext context) {
    // Also re-evaluate when the remote version changes while closed (a newer
    // release must re-trigger the dialog even at the same status).
    return BlocListener<UpdateCubit, UpdateState>(
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.remote?.version != current.remote?.version,
      listener: (context, state) => _showIfDue(),
      child: widget.child,
    );
  }

  void _showIfDue() {
    if (!mounted || _isShowing) return;
    final cubit = context.read<UpdateCubit>();
    final state = cubit.state;
    if (!state.shouldShow(cubit.dismissedVersion)) return;

    // The host sits above the navigator — push the dialog route through the
    // root navigator key directly.
    final navigator = UpdateDialogHost.navigatorKey.currentState;
    if (navigator == null) {
      // Navigator not mounted yet; the next state change / frame re-triggers.
      return;
    }

    _isShowing = true;
    final wasForced = state.isForced;
    unawaited(
      navigator
          .push(
            DialogRoute<void>(
              context: navigator.context,
              builder: (_) => const UpdateAvailableDialog(),
              // Forced dialogs can never be tapped away; available ones can — any
              // close path then counts as "Later".
              barrierDismissible: !wasForced,
              barrierColor: Colors.black54,
              barrierLabel: 'Update dialog',
            ),
          )
          .then((_) async {
            _isShowing = false;
            if (!wasForced) {
              // Dismiss the shown version; a newer one re-triggers automatically.
              // Awaited: _showIfDue must not run while the state is still
              // "available" (pre-dismissal), or the dialog would instantly re-show.
              await cubit.dismissUntilNextVersion();
            }
            // A newer release (or a state change while closed) re-evaluates.
            _showIfDue();
          }),
    );
  }
}
