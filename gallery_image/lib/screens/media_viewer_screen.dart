import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';

import '../controllers/gallery_controller.dart';
import '../utils/media_utils.dart';
import '../utils/video_source.dart';
import '../widgets/media_thumbnail.dart';
import 'photo_edit_screen.dart';

/// Full-screen viewer for the whole media timeline.
///
/// Swiping left/right moves one item at a time through photos and videos.
/// Photos fit within the screen and zoom in place on double tap; videos play
/// inline with transport controls.
/// The status bar stays hidden. Tapping the media shows the controls and the
/// viewer controls, and tapping again hides them. Swiping down
/// closes the viewer on both.
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

  bool dragging = false;
  double dragValue = 0;

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
    // Videos keep their controls visible because tapping plays/pauses them.
    _showControls = currentIsVideo;
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

  /// Applies the current system bar visibility. The status bar stays hidden
  /// for the whole viewer while keeping the bottom navigation bar visible.
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

  // Pinching back to normal size leaves zoom mode, so page swipes work again.
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
      // Photos open clean (tap to show controls); videos keep them on screen.
      _showControls = newIsVideo;
      dragOffset = 0;
      videoController = null;
      videoError = null;
      deleting = false;
      dragging = false;
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

  /// Opens the video with the URL photo_manager provides for players.
  ///
  /// `AssetEntity.file` copies videos into a cache directory on Android and
  /// can fail for large or scoped-storage videos, so the media URL
  /// (`content://` on Android, `file://` on iOS) is tried first. The file is
  /// kept as a fallback.
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
    // Invalidate any in-flight load so it cannot install a stale controller
    // after the deleted/recovered item is removed from the viewer.
    _videoLoadToken++;

    final oldVideo = videoController;

    _videoTransform.value = Matrix4.identity();

    setState(() {
      items.removeAt(currentIndex);
      dragOffset = 0;
      videoController = null;
      videoError = null;
      deleting = false;
      dragging = false;
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
    // Recovering/deleting the last item pops this route, but the setState
    // that removed it still schedules one rebuild. Render a blank frame
    // instead of reading currentItem from an empty list.
    if (items.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final double opacity = (1 - dragOffset / 400).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // While a video is zoomed, drags pan the video instead of closing it.
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
                        child: _ZoomablePhotoPage(
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

    // Show the video's own thumbnail while it opens, so a slow load never
    // flashes the failure message.
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
      onTap: _togglePlayback,
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
            _buildVideoTransport(player),
            const SizedBox(height: 10),
          ],
          _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildVideoTransport(VideoPlayerController player) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
        final positionMs = dragging
            ? dragValue
            : value.position.inMilliseconds.toDouble();
        final shownPosition = dragging
            ? Duration(milliseconds: dragValue.round())
            : value.position;

        return Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  onPressed: _togglePlayback,
                  icon: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: positionMs.clamp(0.0, maxMs).toDouble(),
                    max: maxMs,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: durationMs > 0
                        ? (newValue) {
                            setState(() {
                              dragging = true;
                              dragValue = newValue;
                            });
                          }
                        : null,
                    onChangeEnd: durationMs > 0
                        ? (newValue) async {
                            await player.seekTo(
                              Duration(milliseconds: newValue.round()),
                            );
                            if (!mounted) return;
                            setState(() => dragging = false);
                          }
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                  onPressed: () => player.setVolume(value.volume == 0 ? 1 : 0),
                  icon: Icon(
                    value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  formatMediaDuration(shownPosition.inSeconds),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: () => _seekBy(-10),
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: () => _seekBy(10),
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  formatMediaDuration(value.duration.inSeconds),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        );
      },
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

  /// Favorite toggle, kept in the same row as Delete and Edit.
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

/// A photo fitted to the viewport, with double-tap zoom at the tapped spot.
class _ZoomablePhotoPage extends StatefulWidget {
  const _ZoomablePhotoPage({required this.item, required this.onTap});

  final AssetEntity item;
  final VoidCallback onTap;

  @override
  State<_ZoomablePhotoPage> createState() => _ZoomablePhotoPageState();
}

class _ZoomablePhotoPageState extends State<_ZoomablePhotoPage>
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
  void didUpdateWidget(_ZoomablePhotoPage oldWidget) {
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

  /// The transform that scales around [focalPoint], clamped so the image
  /// never leaves visible empty space.
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

  /// The same photo layout is used for the normal view and the zoom
  /// overlay, so switching between them is seamless.
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
