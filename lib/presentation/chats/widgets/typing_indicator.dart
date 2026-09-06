import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class TypingIndicator extends StatefulWidget {
  final ThemeColors colors;
  final bool isImageGeneration;
  final bool isInitializing;
  final bool isThinking;

  const TypingIndicator({
    super.key,
    required this.colors,
    this.isImageGeneration = false,
    this.isInitializing = false,
    this.isThinking = false,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _syncController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    _syncController();
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    if ((widget.isInitializing && !widget.isThinking) ||
        _disableAnimations) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      return;
    }

    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _calculateOpacity(double value, int dotIndex) {
    final offset = dotIndex * 0.33;
    final adjustedValue = (value + offset) % 1.0;
    if (adjustedValue < 0.5) {
      return adjustedValue * 2;
    }
    return 2 - adjustedValue * 2;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: widget.colors.card,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(20),
            ),
            border: Border.all(
              color: widget.colors.border.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isThinking) ...[
                Text(
                  'Generating response',
                  style: TextStyle(
                    color: widget.colors.subtext,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _BouncingDotRow(
                    controllerValue: _controller.value,
                  ),
                ),
              ] else if (widget.isInitializing) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.colors.subtext,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Initializing model...',
                  style: TextStyle(
                    color: widget.colors.subtext,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else if (widget.isImageGeneration) ...[
                Text(
                  'Generating your image',
                  style: TextStyle(
                    color: widget.colors.subtext,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _DotRow(
                    controllerValue: _controller.value,
                    calculateOpacity: _calculateOpacity,
                  ),
                ),
              ] else ...[
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _DotRow(
                    controllerValue: _controller.value,
                    calculateOpacity: _calculateOpacity,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DotRow extends StatelessWidget {
  final double controllerValue;
  final double Function(double value, int dotIndex) calculateOpacity;

  const _DotRow({
    required this.controllerValue,
    required this.calculateOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DotWidget(
          dotIndex: 0,
          controllerValue: controllerValue,
          calculateOpacity: calculateOpacity,
        ),
        const SizedBox(width: 6),
        _DotWidget(
          dotIndex: 1,
          controllerValue: controllerValue,
          calculateOpacity: calculateOpacity,
        ),
        const SizedBox(width: 6),
        _DotWidget(
          dotIndex: 2,
          controllerValue: controllerValue,
          calculateOpacity: calculateOpacity,
        ),
      ],
    );
  }
}

class _DotWidget extends StatelessWidget {
  final int dotIndex;
  final double controllerValue;
  final double Function(double value, int dotIndex) calculateOpacity;

  const _DotWidget({
    required this.dotIndex,
    required this.controllerValue,
    required this.calculateOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = calculateOpacity(controllerValue, dotIndex);
    return Opacity(
      opacity: 0.4 + 0.6 * opacity,
      child: const _DotShape(),
    );
  }
}

class _DotShape extends StatelessWidget {
  const _DotShape();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: AppColors.amber,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _BouncingDotRow extends StatelessWidget {
  final double controllerValue;

  const _BouncingDotRow({required this.controllerValue});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _bouncingDot(0),
        const SizedBox(width: 6),
        _bouncingDot(1),
        const SizedBox(width: 6),
        _bouncingDot(2),
      ],
    );
  }

  Widget _bouncingDot(int dotIndex) {
    final phase = (controllerValue + dotIndex * 0.2) % 1.0;
    final dy = -7.0 * (0.5 - 0.5 * math.cos(phase * 2 * math.pi));
    return SizedBox(
      width: 7,
      height: 15,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: const _DotShape(),
        ),
      ),
    );
  }
}
