import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../utils/media_utils.dart';
import 'video_badge_widget.dart';

class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({
    super.key,
    required this.asset,
    this.thumbnailSize = const ThumbnailSize(300, 300),
    this.fit = BoxFit.cover,
  });

  final AssetEntity asset;
  final ThumbnailSize thumbnailSize;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AssetEntityImage(
          asset,
          isOriginal: false,
          thumbnailSize: thumbnailSize,
          fit: fit,
        ),
        if (isVideoAsset(asset)) VideoBadge(durationSeconds: asset.duration),
      ],
    );
  }
}
