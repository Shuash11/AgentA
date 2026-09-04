import 'dart:async';

import 'package:flutter/material.dart';

class AnimatedBubble extends StatefulWidget {
  const AnimatedBubble({
    super.key,
    required this.child,
    this.isUser = false,
    this.index = 0,
    this.animate = true,
    this.delay = Duration.zero,
    this.beginOffset,
    this.beginScale = 0.985,
    this.duration = const Duration(milliseconds: 240),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final bool isUser;
  final int index;
  final bool animate;
  final Duration delay;
  final Offset? beginOffset;
  final double beginScale;
  final Duration duration;
  final Curve curve;

  @override
  State<AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.animate ? 0.0 : 1.0,
    );

    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    final horizontalOffset = widget.isUser ? 0.04 : -0.04;
    final beginOffset = widget.beginOffset ?? Offset(horizontalOffset, 0.08);

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slide = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(begin: widget.beginScale, end: 1.0).animate(curved);

    if (widget.animate) {
      final staggerIndex = widget.index.clamp(0, 4).toInt();
      final effectiveDelay = widget.delay == Duration.zero
          ? Duration(milliseconds: staggerIndex * 12)
          : widget.delay;

      if (effectiveDelay == Duration.zero) {
        _controller.forward();
      } else {
        _delayTimer = Timer(effectiveDelay, () {
          if (mounted) {
            _controller.forward();
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _controller.value != 1.0) {
      _delayTimer?.cancel();
      _delayTimer = null;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.animate && _controller.value != 1.0) {
      _delayTimer?.cancel();
      _delayTimer = null;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}
