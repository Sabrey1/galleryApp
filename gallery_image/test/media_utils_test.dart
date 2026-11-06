import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/utils/media_utils.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _asset({
  required String id,
  required AssetType type,
  int duration = 0,
  DateTime? created,
}) {
  return AssetEntity(
    id: id,
    typeInt: type.index,
    width: 100,
    height: 100,
    duration: duration,
    createDateSecond: (created ?? DateTime(2026, 1, 1)).millisecondsSinceEpoch ~/
        1000,
  );
}

void main() {
  group('galleryRequestType', () {
    test('requests both images and videos', () {
      expect(galleryRequestType.containsImage(), isTrue);
      expect(galleryRequestType.containsVideo(), isTrue);
    });
  });

  group('formatMediaDuration', () {
    test('formats zero seconds', () {
      expect(formatMediaDuration(0), '0:00');
    });

    test('pads seconds below one minute', () {
      expect(formatMediaDuration(5), '0:05');
    });

    test('formats minutes and seconds', () {
      expect(formatMediaDuration(125), '2:05');
    });

    test('formats hours, minutes and seconds', () {
      expect(formatMediaDuration(3661), '1:01:01');
    });

    test('treats negative values as zero', () {
      expect(formatMediaDuration(-4), '0:00');
    });
  });

  group('isVideoAsset', () {
    test('returns true for video assets', () {
      final video = _asset(id: 'v1', type: AssetType.video, duration: 30);

      expect(isVideoAsset(video), isTrue);
    });

    test('returns false for image assets', () {
      final image = _asset(id: 'i1', type: AssetType.image);

      expect(isVideoAsset(image), isFalse);
    });
  });

  group('imageAssetsOnly', () {
    test('keeps images in their original order and drops videos', () {
      final imageA = _asset(id: 'a', type: AssetType.image);
      final video = _asset(id: 'v', type: AssetType.video);
      final imageB = _asset(id: 'b', type: AssetType.image);

      final result = imageAssetsOnly([imageA, video, imageB]);

      expect(result.map((asset) => asset.id), ['a', 'b']);
    });
  });

  group('videoAssetsOnly', () {
    test('keeps videos in their original order and drops images', () {
      final videoA = _asset(id: 'v1', type: AssetType.video);
      final image = _asset(id: 'i', type: AssetType.image);
      final videoB = _asset(id: 'v2', type: AssetType.video);

      final result = videoAssetsOnly([videoA, image, videoB]);

      expect(result.map((asset) => asset.id), ['v1', 'v2']);
    });
  });

  group('videoLoadState', () {
    test('is ready when a controller exists', () {
      expect(
        videoLoadState(hasController: true, error: null),
        VideoLoadState.ready,
      );
    });

    test('is still loading when the controller is not ready and there is no error', () {
      expect(
        videoLoadState(hasController: false, error: null),
        VideoLoadState.loading,
      );
    });

    test('fails only when an error is present', () {
      expect(
        videoLoadState(hasController: false, error: 'unsupported'),
        VideoLoadState.failed,
      );
    });
  });

  group('videoZoomMatrix', () {
    test('applies the requested zoom scale', () {
      final matrix = videoZoomMatrix(
        focalPoint: const Offset(100, 50),
        scale: videoDoubleTapZoom,
      );

      expect(matrix.getMaxScaleOnAxis(), closeTo(videoDoubleTapZoom, 1e-9));
    });

    test('keeps the focal point in place while zooming', () {
      final matrix = videoZoomMatrix(
        focalPoint: const Offset(100, 50),
        scale: 2,
      );
      final translation = matrix.getTranslation();

      expect(translation.x, closeTo(-100, 1e-6));
      expect(translation.y, closeTo(-50, 1e-6));
    });
  });

  group('clampSeekPosition', () {
    test('seeks forward by ten seconds', () {
      expect(
        clampSeekPosition(
          position: const Duration(seconds: 5),
          duration: const Duration(seconds: 30),
          seconds: 10,
        ),
        const Duration(seconds: 15),
      );
    });

    test('does not seek before the start', () {
      expect(
        clampSeekPosition(
          position: const Duration(seconds: 5),
          duration: const Duration(seconds: 30),
          seconds: -10,
        ),
        Duration.zero,
      );
    });

    test('does not seek past the end', () {
      expect(
        clampSeekPosition(
          position: const Duration(seconds: 25),
          duration: const Duration(seconds: 30),
          seconds: 10,
        ),
        const Duration(seconds: 30),
      );
    });

    test('seeks backwards from the end', () {
      expect(
        clampSeekPosition(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 30),
          seconds: -10,
        ),
        const Duration(seconds: 20),
      );
    });
  });
}
