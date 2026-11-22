import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../controllers/gallery_controller.dart';
import '../screens/hidden_unlock_screen.dart';
import 'media_thumbnail_widget.dart';

class PhotosTab extends StatefulWidget {
  const PhotosTab({
    super.key,
    required this.controller,
    required this.gridCount,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onOpenPhoto,
  });

  final GalleryController controller;
  final RxInt gridCount;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;
  final void Function(AssetEntity) onOpenPhoto;

  @override
  State<PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<PhotosTab> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedIds = {};
  bool _selecting = false;
  bool _working = false;

  void _toggleSelection(AssetEntity item) {
    if (_working) return;
    setState(() {
      _selecting = true;
      if (!_selectedIds.add(item.id)) _selectedIds.remove(item.id);
    });
  }

  void _finishSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Future<void> _hideSelected() async {
    if (_working || _selectedIds.isEmpty) return;
    setState(() => _working = true);
    try {
      final unlocked = await unlockHiddenAlbum(context);
      if (!mounted || !unlocked) return;
      final items = widget.controller.photos
          .where((item) => _selectedIds.contains(item.id))
          .toList();
      await widget.controller.setPhotosHidden(items, true);
      if (!mounted) return;
      _finishSelection();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${items.length} item(s) hidden')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not hide selected items.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_working || _selectedIds.isEmpty) return;
    final count = widget.controller.photos
        .where((item) => _selectedIds.contains(item.id))
        .length;
    if (count == 0) return;
    setState(() => _working = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Move to Recently Deleted?'),
          content: Text(
            'Move $count selected item(s) to Recently Deleted? You can recover them later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Move'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final items = widget.controller.photos
          .where((item) => _selectedIds.contains(item.id))
          .toList();
      await widget.controller.movePhotosToRecentlyDeleted(items);
      if (!mounted) return;
      _finishSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${items.length} item(s) moved to Recently Deleted'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move selected items.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

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
      final visibleIds = controller.photos.map((item) => item.id).toSet();
      final selectedCount = _selectedIds.intersection(visibleIds).length;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selecting
                        ? '$selectedCount selected'
                        : 'Long-press to select',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (_selecting) ...[
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() {
                            if (selectedCount == visibleIds.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds
                                ..clear()
                                ..addAll(visibleIds);
                            }
                          }),
                    child: Text(
                      selectedCount == visibleIds.length
                          ? 'Deselect all'
                          : 'Select all',
                    ),
                  ),
                  TextButton(
                    onPressed: _working ? null : _finishSelection,
                    child: const Text('Done'),
                  ),
                ] else
                  TextButton(
                    onPressed: () => setState(() => _selecting = true),
                    child: const Text('Select'),
                  ),
              ],
            ),
          ),
          if (_selecting)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _working || selectedCount == 0
                      ? null
                      : _hideSelected,
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: const Text('Hide'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _working || selectedCount == 0
                      ? null
                      : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          Expanded(
            child: GestureDetector(
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
                                    physics:
                                        const NeverScrollableScrollPhysics(),
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
                                        onTap: () => _selecting
                                            ? _toggleSelection(photo)
                                            : onOpenPhoto(photo),
                                        onLongPress: () =>
                                            _toggleSelection(photo),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            MediaThumbnail(asset: photo),
                                            if (_selecting &&
                                                _selectedIds.contains(photo.id))
                                              Container(
                                                color: Colors.black.withAlpha(
                                                  100,
                                                ),
                                                alignment: Alignment.topRight,
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                child: const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.white,
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
                        }, childCount: entries.length),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
