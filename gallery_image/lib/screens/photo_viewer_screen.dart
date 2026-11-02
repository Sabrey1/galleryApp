import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../controllers/gallery_controller.dart';
import 'photo_edit_screen.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<AssetEntity> photos;
  final int initialIndex;
  final bool isRecentlyDeleted;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.isRecentlyDeleted = false,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController pageController;
  late int currentIndex;

  double dragOffset = 0;
  bool deleting = false;

  @override
  void initState() {
    super.initState();

    currentIndex = widget.initialIndex;

    pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  // Swipe down to close viewer.
  void onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy > 0) {
      setState(() {
        dragOffset += details.delta.dy;
      });
    }
  }

  void onVerticalDragEnd(DragEndDetails details) {
    if (dragOffset > 120) {
      Navigator.pop(context);
    } else {
      setState(() {
        dragOffset = 0;
      });
    }
  }

  Future<void> editCurrentPhoto() async {
    final photo = widget.photos[currentIndex];

    final savedPhoto = await Navigator.push<AssetEntity>(
      context,
      MaterialPageRoute(builder: (_) => PhotoEditScreen(photo: photo)),
    );

    if (!mounted) return;

    if (savedPhoto != null) {
      await Get.find<GalleryController>().loadPhotos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Edited photo added to gallery')),
      );
    }
  }

  Future<void> deleteCurrentPhoto() async {
    if (deleting || widget.photos.isEmpty) return;

    final photo = widget.photos[currentIndex];

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
              ? 'This photo will be permanently deleted from your phone. '
                    'This cannot be undone.'
              : 'This photo will be moved to Recently Deleted. '
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

    setState(() {
      deleting = true;
    });

    try {
      final controller = Get.find<GalleryController>();
      if (widget.isRecentlyDeleted) {
        await controller.permanentlyDeletePhotos([photo]);
        if (controller.recentlyDeleted.any((item) => item.id == photo.id)) {
          if (mounted) setState(() => deleting = false);
          return;
        }
      } else {
        await controller.deletePhoto(photo);
      }

      if (!mounted) return;

      _removeCurrentPhoto();
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

  Future<void> recoverCurrentPhoto() async {
    if (deleting || widget.photos.isEmpty) return;

    setState(() => deleting = true);

    try {
      await Get.find<GalleryController>().recoverPhotos([
        widget.photos[currentIndex],
      ]);

      if (!mounted) return;

      _removeCurrentPhoto();
    } catch (e) {
      if (!mounted) return;

      setState(() => deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recover error: $e')));
    }
  }

  void _removeCurrentPhoto() {
    widget.photos.removeAt(currentIndex);

    if (widget.photos.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final nextIndex = currentIndex.clamp(0, widget.photos.length - 1).toInt();

    setState(() {
      currentIndex = nextIndex;
      deleting = false;
      dragOffset = 0;
    });

    pageController.jumpToPage(nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final double opacity = (1 - dragOffset / 400).clamp(0.0, 1.0).toDouble();
    final galleryController = Get.find<GalleryController>();

    return Scaffold(
      backgroundColor: Colors.black,

      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: onVerticalDragUpdate,
        onVerticalDragEnd: onVerticalDragEnd,

        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, dragOffset),

                child: Opacity(
                  opacity: opacity,

                  child: PhotoViewGallery.builder(
                    pageController: pageController,
                    itemCount: widget.photos.length,
                    scrollPhysics: const BouncingScrollPhysics(),

                    onPageChanged: (index) {
                      setState(() {
                        currentIndex = index;
                        dragOffset = 0;
                      });
                    },

                    builder: (context, index) {
                      final photo = widget.photos[index];

                      return PhotoViewGalleryPageOptions(
                        imageProvider: AssetEntityImageProvider(
                          photo,
                          isOriginal: true,
                        ),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 4,
                        initialScale: PhotoViewComputedScale.contained,
                      );
                    },

                    backgroundDecoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),

            // Back button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
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

            // Photo counter
            Positioned(
              top: MediaQuery.of(context).padding.top + 18,
              right: 68,
              child: Text(
                '${currentIndex + 1} / ${widget.photos.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),

            if (!widget.isRecentlyDeleted)
              Positioned(
                top: MediaQuery.of(context).padding.top + 4,
                right: 8,
                child: Obx(() {
                  final photo = widget.photos[currentIndex];
                  final isFavorite = galleryController.isFavorite(photo.id);

                  return IconButton(
                    tooltip: isFavorite
                        ? 'Remove from Favorites'
                        : 'Add to Favorites',
                    onPressed: () => galleryController.toggleFavorite(photo),
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border,
                      color: isFavorite ? Colors.amber : Colors.white,
                      size: 28,
                    ),
                  );
                }),
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

      // Bottom toolbar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFF171717),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: widget.isRecentlyDeleted
                    ? OutlinedButton(
                        onPressed: deleting ? null : deleteCurrentPhoto,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Delete Permanently',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: deleting ? null : deleteCurrentPhoto,
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
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: deleting
                      ? null
                      : widget.isRecentlyDeleted
                      ? recoverCurrentPhoto
                      : editCurrentPhoto,
                  icon: Icon(
                    widget.isRecentlyDeleted
                        ? Icons.restore
                        : Icons.edit_outlined,
                  ),
                  label: Text(widget.isRecentlyDeleted ? 'Recover' : 'Edit'),
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
          ),
        ),
      ),
    );
  }
}
