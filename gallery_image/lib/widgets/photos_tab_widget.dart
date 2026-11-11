import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../controllers/gallery_controller.dart';
import 'media_thumbnail_widget.dart';

class PhotosTab extends StatefulWidget {
  const PhotosTab({
    super.key,
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
  State<PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<PhotosTab> {
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
            child: const Text('Allow Photo & Video Access'),
          ),
        );
      }

      if (controller.photos.isEmpty) {
        return const Center(child: Text('No photos or videos found'));
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
                                  child: MediaThumbnail(asset: photo),
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
