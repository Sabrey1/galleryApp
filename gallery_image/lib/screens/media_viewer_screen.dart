import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';

import '../controllers/gallery_controller.dart';
import '../utils/media_utils.dart';
import '../utils/video_source.dart';
import '../widgets/media_thumbnail_widget.dart';
import '../widgets/zoomable_photo_page_widget.dart';
import '../widgets/video_transport_widget.dart';
import 'photo_edit_screen.dart';

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.isRecentlyDeleted = false,
  }) : assert(items.length > 0, 'At least one item is required.');

  final List<AssetEntity> items;
  final int initialIndex;
  final bool isRecentlyDeleted;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen>
    with WidgetsBindingObserver {
  late final List<AssetEntity> items;
  late final PageController pageController;
  late int currentIndex;

  VideoPlayerController? videoController;

  String? videoError;
  bool deleting = false;
  bool _showControls = false;
  bool _statusBarVisible = true;
  bool _navBarVisible = true;

  double dragOffset = 0;

  int _videoLoadToken = 0;

  final TransformationController _videoTransform = TransformationController();
  bool _videoZoomed = false;
  Offset _videoDoubleTapPosition = Offset.zero;

  AssetEntity get currentItem => items[currentIndex];
  bool get currentIsVideo => isVideoAsset(currentItem);

  @override
  void initState() {
    super.initState();
    items = List<AssetEntity>.of(widget.items);
    currentIndex = widget.initialIndex.clamp(0, items.length - 1).toInt();
    _showControls = false;
    _statusBarVisible = true;
    _navBarVisible = true;
    _applySystemBars();
    pageController = PageController(initialPage: currentIndex);
    WidgetsBinding.instance.addObserver(this);

    if (currentIsVideo) {
      _loadVideoForCurrentItem();
    }
  }

  @override
  void dispose() {
    _statusBarVisible = true;
    _navBarVisible = true;
    _applySystemBars();
    WidgetsBinding.instance.removeObserver(this);
    _videoLoadToken++;
    videoController?.dispose();
    _videoTransform.dispose();
    pageController.dispose();
    super.dispose();
  }

  Future<void> _applySystemBars() async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('gallery_image/updater');
        await channel.invokeMethod<void>('setStatusBarVisible', {
          'visible': _statusBarVisible,
        });
        await channel.invokeMethod<void>('setNavigationBarVisible', {
          'visible': _navBarVisible,
        });
      } on MissingPluginException {
        await _applyFlutterSystemBars();
      }
    } else if (Platform.isIOS) {
      await _applyFlutterSystemBars();
    }
  }

  Future<void> _applyFlutterSystemBars() {
    return SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [
        if (_statusBarVisible) SystemUiOverlay.top,
        if (_navBarVisible) SystemUiOverlay.bottom,
      ],
    );
  }

  void _toggleControls() {
    final visible = !_showControls;
    setState(() {
      _showControls = visible;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      videoController?.pause();
    }
  }

  // Swipe down to close, matching the photo viewer behavior for videos too.
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      dragOffset = (dragOffset + details.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (dragOffset > 120) {
      Navigator.pop(context);
    } else {
      setState(() {
        dragOffset = 0;
      });
    }
  }

  void _onVideoDoubleTapDown(TapDownDetails details) {
    _videoDoubleTapPosition = details.localPosition;
  }

  // Double-tap zooms in around the tapped spot; double-tap again zooms out.
  void _toggleVideoZoom() {
    if (_videoZoomed) {
      _resetVideoZoom();
      return;
    }

    setState(() {
      _videoZoomed = true;
      _videoTransform.value = videoZoomMatrix(
        focalPoint: _videoDoubleTapPosition,
        scale: videoDoubleTapZoom,
      );
    });
  }

  void _resetVideoZoom() {
    _videoTransform.value = Matrix4.identity();

    if (_videoZoomed) {
      setState(() => _videoZoomed = false);
    }
  }

  void _onVideoInteractionEnd(ScaleEndDetails details) {
    if (_videoTransform.value.getMaxScaleOnAxis() <= 1.01) {
      _resetVideoZoom();
    }
  }

  Future<void> _onPageChanged(int index) async {
    if (index == currentIndex) return;

    final oldVideo = videoController;
    final newIsVideo = isVideoAsset(items[index]);
    _videoLoadToken++;

    _videoTransform.value = Matrix4.identity();

    setState(() {
      currentIndex = index;
      _showControls = false;
      dragOffset = 0;
      videoController = null;
      videoError = null;
      deleting = false;
      _videoZoomed = false;
    });

    _statusBarVisible = true;
    _navBarVisible = true;
    _applySystemBars();

    if (oldVideo != null) {
      await oldVideo.dispose();
    }

    if (!mounted) return;

    if (newIsVideo) {
      await _loadVideoForCurrentItem();
    }
  }

  Future<void> _loadVideoForCurrentItem() async {
    final token = ++_videoLoadToken;
    final item = currentItem;

    if (!isVideoAsset(item)) {
      setState(() {
        videoController = null;
        videoError = null;
      });
      return;
    }

    setState(() {
      videoError = null;
    });

    try {
      final player = await _openPlayer(item);

      if (!mounted || token != _videoLoadToken) {
        await player.dispose();
        return;
      }

      setState(() {
        videoController = player;
        videoError = null;
      });
    } catch (e) {
      if (!mounted || token != _videoLoadToken) return;

      debugPrint('Video playback failed for ${item.id}: $e');

      setState(() {
        videoError = e.toString();
        _videoZoomed = false;
      });
    }
  }

  Future<VideoPlayerController> _openPlayer(AssetEntity video) async {
    Object? lastError;

    try {
      final mediaUrl = await video.getMediaUrl();
      final source = resolveVideoSource(
        mediaUrl: mediaUrl,
        isAndroid: Platform.isAndroid,
      );

      if (source != null) {
        final player = _controllerFor(source);

        try {
          await _prepare(player);
          return player;
        } catch (e) {
          lastError = e;
          await player.dispose();
        }
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final file = await video.file;

      if (file != null) {
        final player = VideoPlayerController.file(file);

        try {
          await _prepare(player);
          return player;
        } catch (e) {
          lastError = e;
          await player.dispose();
        }
      }
    } catch (e) {
      lastError = e;
    }

    throw lastError ?? Exception('This video is not available on this device.');
  }

  VideoPlayerController _controllerFor(VideoSource source) {
    switch (source.type) {
      case VideoSourceType.contentUri:
        return VideoPlayerController.contentUri(source.uri);
      case VideoSourceType.file:
        return VideoPlayerController.file(File.fromUri(source.uri));
      case VideoSourceType.network:
        return VideoPlayerController.networkUrl(source.uri);
    }
  }

  Future<void> _prepare(VideoPlayerController player) async {
    await player.initialize();
    await player.setLooping(false);
    await player.play();
  }

  Future<void> _retryVideo() async {
    final oldController = videoController;

    _videoTransform.value = Matrix4.identity();

    setState(() {
      videoController = null;
      videoError = null;
      _videoZoomed = false;
    });

    if (oldController != null) {
      await oldController.dispose();
    }

    await _loadVideoForCurrentItem();
  }

  void _togglePlayback() {
    final player = videoController;

    if (player == null) return;

    if (player.value.isPlaying) {
      player.pause();
    } else {
      if (player.value.isCompleted) {
        player.seekTo(Duration.zero);
      }
      player.play();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final player = videoController;

    if (player == null) return;

    await player.seekTo(
      clampSeekPosition(
        position: player.value.position,
        duration: player.value.duration,
        seconds: seconds,
      ),
    );
  }

  Future<void> editCurrentPhoto() async {
    if (currentIsVideo) return;

    final photo = currentItem;

    _statusBarVisible = true;
    _navBarVisible = true;
    await _applySystemBars();
    if (!mounted) return;
    final savedPhoto = await Navigator.push<AssetEntity>(
      context,
      MaterialPageRoute(builder: (_) => PhotoEditScreen(photo: photo)),
    );

    if (!mounted) return;
    _statusBarVisible = true;
    _navBarVisible = true;
    await _applySystemBars();
    if (!mounted) return;

    if (savedPhoto != null) {
      await Get.find<GalleryController>().loadPhotos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Edited photo added to gallery')),
      );
    }
  }

  Future<void> deleteCurrentItem() async {
    if (deleting || items.isEmpty) return;

    final item = currentItem;
    final noun = currentIsVideo ? 'video' : 'photo';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.isRecentlyDeleted
              ? 'Delete permanently?'
              : 'Move to Recently Deleted?',
        ),
        content: Text(
          widget.isRecentlyDeleted
              ? 'This $noun will be permanently deleted from your phone. '
                    'This cannot be undone.'
              : 'This $noun will be moved to Recently Deleted. '
                    'You can recover it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              widget.isRecentlyDeleted ? 'Delete Permanently' : 'Move',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    videoController?.pause();
    setState(() {
      deleting = true;
    });

    try {
      final gallery = Get.find<GalleryController>();

      if (widget.isRecentlyDeleted) {
        await gallery.permanentlyDeletePhotos([item]);

        if (gallery.recentlyDeleted.any((asset) => asset.id == item.id)) {
          if (mounted) setState(() => deleting = false);
          return;
        }
      } else {
        await gallery.deletePhoto(item);
      }

      if (!mounted) return;

      await _removeCurrentItem();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        deleting = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

  Future<void> recoverCurrentItem() async {
    if (deleting || items.isEmpty) return;

    final item = currentItem;

    videoController?.pause();
    setState(() => deleting = true);

    try {
      await Get.find<GalleryController>().recoverPhotos([item]);

      if (!mounted) return;

      await _removeCurrentItem();
    } catch (e) {
      if (!mounted) return;

      setState(() => deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recover error: $e')));
    }
  }

  Future<void> _removeCurrentItem() async {
    _videoLoadToken++;

    final oldVideo = videoController;

    _videoTransform.value = Matrix4.identity();

    setState(() {
      items.removeAt(currentIndex);
      dragOffset = 0;
      videoController = null;
      videoError = null;
      deleting = false;
      _videoZoomed = false;
    });

    if (items.isEmpty) {
      if (oldVideo != null) {
        await oldVideo.dispose();
      }

      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final nextIndex = currentIndex.clamp(0, items.length - 1).toInt();

    setState(() {
      currentIndex = nextIndex;
      _showControls = false;
    });

    if (pageController.hasClients) {
      pageController.jumpToPage(nextIndex);
    }

    if (oldVideo != null) {
      await oldVideo.dispose();
    }

    if (!mounted) return;

    if (isVideoAsset(items[nextIndex])) {
      await _loadVideoForCurrentItem();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final double opacity = (1 - dragOffset / 400).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _videoZoomed ? null : _onVerticalDragUpdate,
        onVerticalDragEnd: _videoZoomed ? null : _onVerticalDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, dragOffset),
                child: Opacity(
                  opacity: opacity,
                  child: PhotoViewGallery.builder(
                    pageController: pageController,
                    itemCount: items.length,
                    scrollPhysics: const BouncingScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    backgroundDecoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                    builder: (context, index) {
                      final item = items[index];

                      if (isVideoAsset(item)) {
                        return PhotoViewGalleryPageOptions.customChild(
                          child: _buildVideoPage(index),
                          disableGestures: true,
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.contained,
                          initialScale: PhotoViewComputedScale.contained,
                        );
                      }

                      // Fit the whole photo on screen and support double-tap zoom.
                      return PhotoViewGalleryPageOptions.customChild(
                        child: ZoomablePhotoPage(
                          item: item,
                          onTap: _toggleControls,
                        ),
                        disableGestures: true,
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.contained,
                        initialScale: PhotoViewComputedScale.contained,
                      );
                    },
                  ),
                ),
              ),
            ),

            // Back button
            if (_showControls)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),

            // Item counter
            if (_showControls)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 18,
                right: 16,
                child: Text(
                  '${currentIndex + 1} / ${items.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),

            if (_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _buildBottomBar(),
                    ),
                  ),
                ),
              ),

            if (deleting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPage(int index) {
    if (index != currentIndex) {
      return _buildPreview(items[index]);
    }

    final item = items[index];
    final player = videoController;
    final state = videoLoadState(
      hasController: player != null,
      error: videoError,
    );

    if (state == VideoLoadState.failed) {
      return _buildVideoError();
    }

    if (player == null) {
      return _buildVideoLoading(item);
    }

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: player.value.aspectRatio,
            child: VideoPlayer(player),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: player,
          builder: (context, value, _) {
            if (value.isPlaying) {
              return const SizedBox.shrink();
            }

            return IgnorePointer(
              child: Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      value.isCompleted
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTapDown: _onVideoDoubleTapDown,
      onDoubleTap: _toggleVideoZoom,
      // InteractiveViewer only wraps the video while zoomed, so horizontal
      // page swipes and swipe-down-to-close still work at normal size.
      child: _videoZoomed
          ? InteractiveViewer(
              transformationController: _videoTransform,
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled: true,
              scaleEnabled: true,
              onInteractionEnd: _onVideoInteractionEnd,
              child: content,
            )
          : content,
    );
  }

  Widget _buildVideoLoading(AssetEntity video) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreview(video),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildVideoError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 12),
            const Text(
              'Cannot play this video',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              videoError ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retryVideo,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AssetEntity video) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: MediaThumbnail(
          asset: video,
          thumbnailSize: const ThumbnailSize(600, 600),
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final player = videoController;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xE61A1A1A),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentIsVideo && player != null) ...[
            VideoTransport(
              key: ObjectKey(player),
              player: player,
              onTogglePlayback: _togglePlayback,
              onSeekBy: _seekBy,
            ),
            const SizedBox(height: 10),
          ],
          _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    final isVideo = currentIsVideo;

    if (widget.isRecentlyDeleted) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: deleting ? null : deleteCurrentItem,
              icon: const Icon(Icons.delete_forever),
              label: const Text(
                'Delete Permanently',
                textAlign: TextAlign.center,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: deleting ? null : recoverCurrentItem,
              icon: const Icon(Icons.restore),
              label: const Text('Recover'),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        _buildFavoriteButton(),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: deleting ? null : deleteCurrentItem,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (!isVideo) ...[
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: deleting ? null : editCurrentPhoto,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFavoriteButton() {
    final galleryController = Get.find<GalleryController>();

    return Obx(() {
      final item = currentItem;
      final isFavorite = galleryController.isFavorite(item.id);

      return SizedBox(
        width: 56,
        height: 48,
        child: OutlinedButton(
          onPressed: deleting
              ? null
              : () => galleryController.toggleFavorite(item),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: isFavorite ? Colors.amber : Colors.white24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Icon(
            isFavorite ? Icons.star : Icons.star_border,
            color: isFavorite ? Colors.amber : Colors.white,
            size: 28,
          ),
        ),
      );
    });
  }
}
