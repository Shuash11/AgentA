import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'auto_retry_image.dart';

class ImageBubbleContent extends StatefulWidget {
  final String imageUrl;
  final ThemeColors colors;
  final double width;
  final Future<void> Function()? onFallbackRequested;
  final bool fallbackAvailable;

  const ImageBubbleContent({
    super.key,
    required this.imageUrl,
    required this.colors,
    required this.width,
    this.onFallbackRequested,
    this.fallbackAvailable = false,
  });

  @override
  State<ImageBubbleContent> createState() => _ImageBubbleContentState();
}

class _ImageBubbleContentState extends State<ImageBubbleContent> {
  bool _isLoaded = false;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: widget.width,
              height: widget.width,
              child: AutoRetryImage(
                imageUrl: widget.imageUrl,
                colors: widget.colors,
                width: widget.width,
                onFallbackRequested: widget.onFallbackRequested,
                fallbackAvailable: widget.fallbackAvailable,
                onImageLoaded: _isLoaded
                    ? null
                    : () {
                        if (mounted) {
                          setState(() => _isLoaded = true);
                        }
                      },
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isLoaded ? 1.0 : 0.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Generated image',
                  style: TextStyle(
                    color: widget.colors.subtext,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
