import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../controllers/gallery_controller.dart';
import 'media_thumbnail_widget.dart';

class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key, required this.controller, required this.onOpenPhoto});

  final GalleryController controller;
  final void Function(AssetEntity) onOpenPhoto;

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
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
              child: MediaThumbnail(asset: photo),
            );
          },
        ),
      );
    });
  }
}
