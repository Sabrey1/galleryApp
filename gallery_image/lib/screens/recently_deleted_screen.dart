import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../controllers/gallery_controller.dart';
import 'photo_viewer_screen.dart';

class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  final GalleryController controller = Get.find<GalleryController>();

  final Set<String> selectedIds = {};
  final ScrollController _scrollController = ScrollController();

  bool get isSelecting => selectedIds.isNotEmpty;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<AssetEntity> get selectedPhotos {
    return controller.recentlyDeleted
        .where((photo) => selectedIds.contains(photo.id))
        .toList();
  }

  void toggleSelection(AssetEntity photo) {
    setState(() {
      if (selectedIds.contains(photo.id)) {
        selectedIds.remove(photo.id);
      } else {
        selectedIds.add(photo.id);
      }
    });
  }

  void selectAll() {
    setState(() {
      if (selectedIds.length == controller.recentlyDeleted.length) {
        selectedIds.clear();
      } else {
        selectedIds.addAll(controller.recentlyDeleted.map((photo) => photo.id));
      }
    });
  }

  void clearSelection() {
    setState(() {
      selectedIds.clear();
    });
  }

  Future<void> recoverSelected() async {
    final photos = selectedPhotos;

    if (photos.isEmpty) return;

    clearSelection();
    await controller.recoverPhotos(photos);
  }

  Future<void> deleteSelected() async {
    final photos = selectedPhotos;

    if (photos.isEmpty) return;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'Permanently delete ${photos.length} selected photo(s) '
          'from your phone? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      clearSelection();
      await controller.permanentlyDeletePhotos(photos);
    }
  }

  Future<void> emptyTrash() async {
    if (controller.recentlyDeleted.isEmpty) return;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Empty Recently Deleted?'),
        content: const Text(
          'All photos in Recently Deleted will be permanently '
          'deleted from your phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Empty', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      clearSelection();
      await controller.emptyRecentlyDeleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final photos = controller.recentlyDeleted.toList();

      if (photos.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 70, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'Recently Deleted is Empty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Deleted photos will appear here.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      }

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  isSelecting
                      ? '${selectedIds.length} selected'
                      : '${photos.length} photos',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (isSelecting) ...[
                  TextButton(
                    onPressed: selectAll,
                    child: Text(
                      selectedIds.length == photos.length
                          ? 'Deselect All'
                          : 'Select All',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recover selected',
                    onPressed: recoverSelected,
                    icon: const Icon(Icons.restore, color: Colors.green),
                  ),
                  IconButton(
                    tooltip: 'Delete selected permanently',
                    onPressed: deleteSelected,
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: emptyTrash,
                    child: const Text(
                      'Empty',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Long-press a photo to select multiple photos.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
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
                  final selected = selectedIds.contains(photo.id);

                  return GestureDetector(
                    onTap: () {
                      if (isSelecting) {
                        toggleSelection(photo);
                      } else {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => PhotoViewerScreen(
                              photos: photos,
                              initialIndex: index,
                              isRecentlyDeleted: true,
                            ),
                          ),
                        );
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => toggleSelection(photo),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AssetEntityImage(
                          photo,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize(300, 300),
                          fit: BoxFit.cover,
                        ),
                        if (selected)
                          Container(
                            color: Colors.black.withAlpha(100),
                            child: const Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: EdgeInsets.all(5),
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    });
  }
}
