import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../controllers/gallery_controller.dart';
import 'photo_viewer_screen.dart';
import 'recently_deleted_screen.dart';
import 'update_screen.dart';

class GalleryScreen extends StatelessWidget {
  GalleryScreen({super.key});

  final GalleryController controller = Get.put(GalleryController());

  final RxInt gridCount = 4.obs;
  final RxDouble _startScale = 1.0.obs;

  void _onScaleStart(ScaleStartDetails details) {
    _startScale.value = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final difference = details.scale - _startScale.value;

    if (difference > 0.08) {
      if (gridCount.value > 2) {
        gridCount.value--;
      }
      _startScale.value = details.scale;
    } else if (difference < -0.08) {
      if (gridCount.value < 8) {
        gridCount.value++;
      }
      _startScale.value = details.scale;
    }
  }

  void _openPhoto(AssetEntity photo) {
    final allPhotos = controller.photos.toList();
    final index = allPhotos.indexOf(photo);

    if (index == -1) return;

    Get.to(() => PhotoViewerScreen(photos: allPhotos, initialIndex: index));
  }

  void _openFavoritePhoto(AssetEntity photo) {
    final favoritePhotos = controller.favorites.toList();
    final index = favoritePhotos.indexOf(photo);

    if (index == -1) return;

    Get.to(
      () => PhotoViewerScreen(photos: favoritePhotos, initialIndex: index),
    );
  }

  void _confirmDelete(AssetEntity photo) {
    Get.dialog(
      AlertDialog(
        title: const Text('Move to Recently Deleted?'),
        content: const Text(
          'This photo will be moved to Recently Deleted. '
          'You can recover it later.',
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Get.back();
              controller.deletePhoto(photo);
            },
            child: const Text('Move', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text(
            'Gallery V3',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.system_update),
              tooltip: 'App Update',
              onPressed: () {
                Get.to(() => UpdateScreen());
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: controller.loadPhotos,
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _PhotosTab(
              controller: controller,
              gridCount: gridCount,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onOpenPhoto: _openPhoto,
              onDeletePhoto: _confirmDelete,
            ),
            _FavoritesTab(
              controller: controller,
              onOpenPhoto: _openFavoritePhoto,
            ),
            const RecentlyDeletedScreen(),
          ],
        ),
        bottomNavigationBar: Material(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontSize: 12),
              tabs: const [
                Tab(
                  height: 60,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.photo_library, size: 25),
                  text: 'Photos',
                ),
                Tab(
                  height: 60,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.star, size: 25),
                  text: 'Favorites',
                ),
                Tab(
                  height: 60,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.delete_outline, size: 25),
                  text: 'Recently Deleted',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotosTab extends StatefulWidget {
  const _PhotosTab({
    required this.controller,
    required this.gridCount,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onOpenPhoto,
    required this.onDeletePhoto,
  });

  final GalleryController controller;
  final RxInt gridCount;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;
  final void Function(AssetEntity) onOpenPhoto;
  final void Function(AssetEntity) onDeletePhoto;

  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final gridCount = widget.gridCount;
    final onScaleStart = widget.onScaleStart;
    final onScaleUpdate = widget.onScaleUpdate;
    final onOpenPhoto = widget.onOpenPhoto;
    final onDeletePhoto = widget.onDeletePhoto;

    return Obx(() {
      if (controller.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (!controller.permissionGranted.value) {
        return Center(
          child: ElevatedButton(
            onPressed: () async {
              await PhotoManager.openSetting();
              await controller.loadPhotos();
            },
            child: const Text('Allow Photo Access'),
          ),
        );
      }

      if (controller.photos.isEmpty) {
        return const Center(child: Text('No photos found'));
      }

      final entries = controller.groupedPhotos.entries.toList();

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        child: RefreshIndicator(
          onRefresh: controller.loadPhotos,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: false,
            interactive: true,
            thickness: 12,
            radius: const Radius.circular(8),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final entry = entries[index];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            index == 0 ? 12 : 24,
                            4,
                            8,
                          ),
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Obx(
                          () => AnimatedSize(
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: GridView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: entry.value.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: gridCount.value,
                                    crossAxisSpacing: 2,
                                    mainAxisSpacing: 2,
                                  ),
                              itemBuilder: (context, photoIndex) {
                                final photo = entry.value[photoIndex];

                                return GestureDetector(
                                  onTap: () => onOpenPhoto(photo),
                                  onLongPress: () => onDeletePhoto(photo),
                                  child: SizedBox.expand(
                                    child: AssetEntityImage(
                                      photo,
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize(
                                        300,
                                        300,
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  }, childCount: entries.length),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _FavoritesTab extends StatefulWidget {
  const _FavoritesTab({required this.controller, required this.onOpenPhoto});

  final GalleryController controller;
  final void Function(AssetEntity) onOpenPhoto;

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final photos = widget.controller.favorites.toList();

      if (photos.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_border, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text('No favorites yet'),
            ],
          ),
        );
      }

      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: false,
        interactive: true,
        thickness: 12,
        radius: const Radius.circular(8),
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(2),
          itemCount: photos.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final photo = photos[index];

            return GestureDetector(
              onTap: () => widget.onOpenPhoto(photo),
              child: AssetEntityImage(
                photo,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize(300, 300),
                fit: BoxFit.cover,
              ),
            );
          },
        ),
      );
    });
  }
}
