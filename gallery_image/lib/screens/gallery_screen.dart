import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../controllers/gallery_controller.dart';
import '../widgets/favorites_tab_widget.dart';
import '../widgets/photos_tab_widget.dart';
import 'media_viewer_screen.dart';
import 'recently_deleted_screen.dart';
import 'update_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final GalleryController controller = Get.put(GalleryController());

  final RxInt gridCount = 4.obs;
  final RxDouble _startScale = 1.0.obs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _manageMediaAccess());
  }

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

  void _openPhoto(AssetEntity asset) {
    final items = controller.photos.toList();
    final index = items.indexWhere((item) => item.id == asset.id);

    if (index == -1) return;

    Get.to(() => MediaViewerScreen(items: items, initialIndex: index));
  }

  void _openFavoritePhoto(AssetEntity asset) {
    final items = controller.favorites.toList();
    final index = items.indexWhere((item) => item.id == asset.id);

    if (index == -1) return;

    Get.to(() => MediaViewerScreen(items: items, initialIndex: index));
  }

  void _confirmDelete(AssetEntity photo) {
    Get.dialog(
      AlertDialog(
        title: const Text('Move to Recently Deleted?'),
        content: const Text(
          'This item will be moved to Recently Deleted. '
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

  Future<void> _manageMediaAccess() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await controller.initialLoad;
    if (!mounted) return;
    const channel = MethodChannel('gallery_image/updater');
    final sdk = await channel.invokeMethod<int>('androidSdkVersion');
    if (!mounted || sdk == null || sdk < 31) return;
    if (await PhotoManager.canManageMedia() || !mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media management access'),
        content: const Text(
          'Allow media management access in Settings to avoid an extra '
          'Android confirmation when permanently deleting photos and videos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (openSettings == true && !await PhotoManager.requestManageMedia()) {
      Get.snackbar(
        'Settings unavailable',
        'Media management access requires Android 12 or later.',
      );
    }
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
            'Gallery',
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
          ],
        ),
        body: TabBarView(
          children: [
            PhotosTab(
              controller: controller,
              gridCount: gridCount,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onOpenPhoto: _openPhoto,
              onDeletePhoto: _confirmDelete,
            ),
            FavoritesTab(
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
