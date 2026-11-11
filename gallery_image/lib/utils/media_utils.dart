import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

const RequestType galleryRequestType = RequestType.common;

/// Whether [asset] is a video.
bool isVideoAsset(AssetEntity asset) => asset.type == AssetType.video;

/// Formats a media duration (in seconds) as `m:ss` or `h:mm:ss`.
String formatMediaDuration(int seconds) {
  final total = seconds > 0 ? seconds : 0;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final remainingSeconds = total % 60;
  final padded = remainingSeconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$padded';
  }

  return '$minutes:$padded';
}

List<AssetEntity> imageAssetsOnly(Iterable<AssetEntity> assets) {
  return assets.where((asset) => asset.type == AssetType.image).toList();
}

/// Returns only video assets, preserving their original order.
List<AssetEntity> videoAssetsOnly(Iterable<AssetEntity> assets) {
  return assets.where(isVideoAsset).toList();
}

/// The visual state of a video page.
enum VideoLoadState { loading, ready, failed }

VideoLoadState videoLoadState({
  required bool hasController,
  required String? error,
}) {
  if (hasController) return VideoLoadState.ready;
  if (error != null) return VideoLoadState.failed;
  return VideoLoadState.loading;
}

/// Zoom scale applied to a video on double-tap.
const double videoDoubleTapZoom = 2.5;


Matrix4 videoZoomMatrix({
  required Offset focalPoint,
  required double scale,
}) {
  return Matrix4.identity()
    ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
}

/// Moves [position] by [seconds], clamped to the video's bounds.
Duration clampSeekPosition({
  required Duration position,
  required Duration duration,
  required int seconds,
}) {
  final target = position + Duration(seconds: seconds);

  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;

  return target;
}
