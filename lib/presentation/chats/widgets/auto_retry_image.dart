import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AutoRetryImage extends StatefulWidget {
  final String imageUrl;
  final ThemeColors colors;
  final double width;
  final VoidCallback? onImageLoaded;

  const AutoRetryImage({
    super.key,
    required this.imageUrl,
    required this.colors,
    required this.width,
    this.onImageLoaded,
  });

  @override
  State<AutoRetryImage> createState() => _AutoRetryImageState();
}

class _AutoRetryImageState extends State<AutoRetryImage> {
  int _retryCount = 0;
  bool _hasError = false;
  bool _notifiedLoaded = false;

  @override
  void didUpdateWidget(covariant AutoRetryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _retryCount = 0;
      _hasError = false;
      _notifiedLoaded = false;
    }
  }

  void _retry() {
    setState(() {
      _retryCount++;
      _hasError = false;
      _notifiedLoaded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorPlaceholder();
    final cacheWidth =
        (widget.width * MediaQuery.devicePixelRatioOf(context)).round();

    return Image.network(
      widget.imageUrl,
      key: ValueKey('${widget.imageUrl}_$_retryCount'),
      fit: BoxFit.cover,
      width: widget.width,
      height: widget.width,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AgentA/1.0',
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildLoadingPlaceholder(loadingProgress);
      },
      errorBuilder: (context, error, stackTrace) {
        if (!_hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_hasError) {
              setState(() => _hasError = true);
            }
          });
        }
        return _buildErrorPlaceholder();
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) return _buildStaticPlaceholder();

        if (!_notifiedLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_notifiedLoaded) {
              _notifiedLoaded = true;
              widget.onImageLoaded?.call();
            }
          });
        }

        return child;
      },
    );
  }

  Widget _buildStaticPlaceholder() {
    return Container(
      key: const ValueKey('placeholder'),
      color: widget.colors.input,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            color: widget.colors.subtext.withValues(alpha: 0.5),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'Image',
            style: TextStyle(
              color: widget.colors.subtext.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder(ImageChunkEvent loadingProgress) {
    final expectedBytes = loadingProgress.expectedTotalBytes;
    final progress = expectedBytes != null
        ? loadingProgress.cumulativeBytesLoaded / expectedBytes
        : null;

    return Container(
      color: widget.colors.input,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: progress != null
                ? CircularProgressIndicator(
                    value: progress,
                    color: widget.colors.amber,
                    backgroundColor: widget.colors.border,
                    strokeWidth: 2,
                  )
                : Icon(
                    Icons.image_outlined,
                    color: widget.colors.subtext.withValues(alpha: 0.5),
                    size: 32,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            progress != null ? 'Loading...' : 'Image',
            style: TextStyle(
              color: widget.colors.subtext,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      key: const ValueKey('error'),
      color: widget.colors.input,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined,
              color: widget.colors.subtext, size: 32),
          const SizedBox(height: 12),
          Text(
            'Image failed to load',
            style: TextStyle(color: widget.colors.subtext, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: Icon(Icons.refresh, color: widget.colors.amber, size: 18),
            label: Text('Retry', style: TextStyle(color: widget.colors.amber)),
            onPressed: _retry,
          ),
        ],
      ),
    );
  }
}
