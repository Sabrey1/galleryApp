import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/gallery_controller.dart';
import '../widgets/media_thumbnail_widget.dart';
import 'hidden_unlock_screen.dart';
import 'media_viewer_screen.dart';

class HiddenAlbumScreen extends StatefulWidget {
  const HiddenAlbumScreen({super.key});

  @override
  State<HiddenAlbumScreen> createState() => _HiddenAlbumScreenState();
}

class _HiddenAlbumScreenState extends State<HiddenAlbumScreen>
    with WidgetsBindingObserver {
  bool unlocked = false;
  bool authenticating = false;
  bool managingLock = false;
  final gallery = Get.find<GalleryController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (unlocked) setState(() => unlocked = false);
    }
  }

  Future<void> unlock() async {
    if (authenticating || !mounted) return;
    authenticating = true;
    final result = await unlockHiddenAlbum(context);
    authenticating = false;
    if (mounted) setState(() => unlocked = result);
  }

  Future<void> manageLock({required bool disable}) async {
    if (managingLock || !unlocked) return;
    setState(() => managingLock = true);
    try {
      if (disable) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Turn off hidden album lock?'),
            content: const Text(
              'All hidden photos and videos will return to Photos. '
              'You can set up a new lock the next time you hide an item.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn off'),
              ),
            ],
          ),
        );
        if (!mounted || !unlocked || confirmed != true) return;
      }
      final verified = await unlockHiddenAlbum(context);
      if (!mounted || !unlocked || !verified) return;
      if (disable) {
        await gallery.initialLoad;
        if (!mounted || !unlocked) return;
        if (gallery.loading.value) {
          throw StateError('The gallery is still loading.');
        }
        await gallery.disableHiddenLock();
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hidden album lock turned off')),
        );
      } else {
        final changed = await changeHiddenAlbumLock(context);
        if (!mounted || !unlocked || !changed) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hidden album lock changed')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update the lock. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => managingLock = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hidden album'),
        actions: [
          if (unlocked)
            PopupMenuButton<bool>(
              tooltip: 'Hidden album settings',
              enabled: !managingLock,
              onSelected: (disable) => manageLock(disable: disable),
              itemBuilder: (context) => const [
                PopupMenuItem(value: false, child: Text('Change lock')),
                PopupMenuItem(value: true, child: Text('Turn off lock')),
              ],
            ),
          if (unlocked)
            IconButton(
              tooltip: 'Lock album',
              icon: const Icon(Icons.lock_outline),
              onPressed: managingLock
                  ? null
                  : () => setState(() => unlocked = false),
            ),
        ],
      ),
      body: !unlocked
          ? Center(
              child: FilledButton.icon(
                onPressed: unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock hidden album'),
              ),
            )
          : Obx(() {
              final items = gallery.hiddenPhotos.toList();
              if (items.isEmpty) {
                return const Center(child: Text('No hidden photos or videos'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaViewerScreen(
                        items: items,
                        initialIndex: index,
                        isHidden: true,
                      ),
                    ),
                  ),
                  child: MediaThumbnail(asset: items[index]),
                ),
              );
            }),
    );
  }
}
