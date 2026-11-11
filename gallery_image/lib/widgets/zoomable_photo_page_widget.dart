import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// A photo fitted to the viewport, with double-tap zoom at the tapped spot.
class ZoomablePhotoPage extends StatefulWidget {
  const ZoomablePhotoPage({super.key, required this.item, required this.onTap});

  final AssetEntity item;
  final VoidCallback onTap;

  @override
  State<ZoomablePhotoPage> createState() => _ZoomablePhotoPageState();
}

class _ZoomablePhotoPageState extends State<ZoomablePhotoPage>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;
  static const double _maxScale = 5.0;

  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _zoomAnimationController;

  Animation<Matrix4>? _zoomAnimation;
  Size _viewportSize = Size.zero;
  Offset _doubleTapPosition = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoomAnimationController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 220),
          )
          ..addListener(_handleZoomAnimation)
          ..addStatusListener(_handleZoomAnimationStatus);
  }

  @override
  void didUpdateWidget(ZoomablePhotoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _zoomed = false;
      _zoomAnimation = null;
      _transformController.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _zoomAnimationController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  double get _scrollOffset => 0.0;

  void _handleZoomAnimation() {
    final animation = _zoomAnimation;
    if (animation != null) {
      _transformController.value = animation.value;
    }
  }

  void _handleZoomAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_transformController.value.getMaxScaleOnAxis() <= 1.01 && _zoomed) {
      setState(() => _zoomed = false);
      _transformController.value = Matrix4.identity();
    }
  }

  void _animateTo(Matrix4 target) {
    _zoomAnimation =
        Matrix4Tween(begin: _transformController.value, end: target).animate(
          CurvedAnimation(
            parent: _zoomAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _zoomAnimationController
      ..value = 0.0
      ..forward();
  }

  /// The transform that matches the unzoomed view.
  Matrix4 _baseMatrix(double offsetY) {
    final matrix = Matrix4.identity();
    matrix.setEntry(1, 3, -offsetY);
    return matrix;
  }

  Matrix4 _zoomMatrix(Offset focalPoint) {
    final Size viewport = _viewportSize;
    final Size content = viewport;
    final double scale = _doubleTapScale;

    final double sceneX = focalPoint.dx;
    final double sceneY = focalPoint.dy + _scrollOffset;
    double tx = focalPoint.dx - sceneX * scale;
    double ty = focalPoint.dy - sceneY * scale;

    final double scaledWidth = content.width * scale;
    final double scaledHeight = content.height * scale;

    if (scaledWidth <= viewport.width) {
      tx = (viewport.width - scaledWidth) / 2;
    } else {
      tx = tx.clamp(viewport.width - scaledWidth, 0.0).toDouble();
    }
    if (scaledHeight <= viewport.height) {
      ty = (viewport.height - scaledHeight) / 2;
    } else {
      ty = ty.clamp(viewport.height - scaledHeight, 0.0).toDouble();
    }

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, scale);
    matrix.setEntry(1, 1, scale);
    matrix.setEntry(0, 3, tx);
    matrix.setEntry(1, 3, ty);
    return matrix;
  }

  void _handleDoubleTap() {
    if (_viewportSize == Size.zero) return;
    final double offsetY = _scrollOffset;

    if (_transformController.value.getMaxScaleOnAxis() > 1.01) {
      _animateTo(_baseMatrix(offsetY));
      return;
    }

    final Matrix4 target = _zoomMatrix(_doubleTapPosition);
    _transformController.value = _baseMatrix(offsetY);
    setState(() => _zoomed = true);
    _animateTo(target);
  }

  void _rememberDoubleTapPosition(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _viewportSize = viewport;

        return Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onDoubleTapDown: _rememberDoubleTapPosition,
              onDoubleTap: _handleDoubleTap,
              child: _buildPhoto(viewport.width, constraints.maxHeight),
            ),
            if (_zoomed)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onDoubleTapDown: _rememberDoubleTapPosition,
                  onDoubleTap: _handleDoubleTap,
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    constrained: false,
                    minScale: 1.0,
                    maxScale: _maxScale,
                    onInteractionStart: (_) {
                      _zoomAnimationController.stop();
                      _zoomAnimation = null;
                    },
                    onInteractionEnd: (_) {
                      if (_transformController.value.getMaxScaleOnAxis() <=
                          1.01) {
                        _animateTo(_baseMatrix(_scrollOffset));
                      }
                    },
                    child: _buildPhoto(viewport.width, constraints.maxHeight),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPhoto(double width, double minHeight) {
    return ConstrainedBox(
      constraints: BoxConstraints.tight(Size(width, minHeight)),
      child: Center(
        child: Image(
          image: AssetEntityImageProvider(widget.item, isOriginal: true),
          width: width,
          height: minHeight,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (_, _, _) => const SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Cannot load this photo',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
