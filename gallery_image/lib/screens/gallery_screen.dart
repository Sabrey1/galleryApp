import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../controllers/gallery_controller.dart';
import '../widgets/favorites_tab_widget.dart';
import '../widgets/photos_tab_widget.dart';
import 'media_viewer_screen.dart';
import 'hidden_album_screen.dart';
import 'recently_deleted_screen.dart';
import 'update_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

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

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Settings',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Appearance'),
              subtitle: Text(switch (widget.themeMode) {
                ThemeMode.system => 'System default',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
              }),
              onTap: () async {
                final mode = await showDialog<ThemeMode>(
                  context: sheetContext,
                  builder: (dialogContext) => SimpleDialog(
                    title: const Text('Appearance'),
                    children: [
                      for (final entry in const [
                        (
                          ThemeMode.system,
                          'System default',
                          Icons.brightness_auto_outlined,
                        ),
                        (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                        (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                      ])
                        SimpleDialogOption(
                          onPressed: () =>
                              Navigator.pop(dialogContext, entry.$1),
                          child: Row(
                            children: [
                              Icon(entry.$3),
                              const SizedBox(width: 12),
                              Expanded(child: Text(entry.$2)),
                              if (widget.themeMode == entry.$1)
                                const Icon(Icons.check),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
                if (!mounted || !sheetContext.mounted || mode == null) return;
                widget.onThemeChanged(mode);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Hidden album'),
              subtitle: const Text('Manage hidden items and lock'),
              onTap: () {
                Navigator.pop(sheetContext);
                Get.to(() => const HiddenAlbumScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('App Update'),
              onTap: () {
                Navigator.pop(sheetContext);
                Get.to(() => UpdateScreen());
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Gallery',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: _showSettings,
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
            ),
            FavoritesTab(
              controller: controller,
              onOpenPhoto: _openFavoritePhoto,
            ),
            const RecentlyDeletedScreen(),
          ],
        ),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
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
