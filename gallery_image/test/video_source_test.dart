import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/utils/video_source.dart';

void main() {
  group('resolveVideoSource', () {
    test('maps an Android content URI to a content URI source', () {
      final source = resolveVideoSource(
        mediaUrl: 'content://media/external/video/media/42',
        isAndroid: true,
      );

      expect(source, isNotNull);
      expect(source!.type, VideoSourceType.contentUri);
      expect(source.uri.toString(), 'content://media/external/video/media/42');
    });

    test('ignores a content URI on non-Android platforms', () {
      final source = resolveVideoSource(
        mediaUrl: 'content://media/external/video/media/42',
        isAndroid: false,
      );

      expect(source, isNull);
    });

    test('maps a file URL to a file source', () {
      final source = resolveVideoSource(
        mediaUrl: 'file:///var/mobile/Media/DCIM/IMG_0001.MOV',
        isAndroid: false,
      );

      expect(source, isNotNull);
      expect(source!.type, VideoSourceType.file);
      expect(source.uri.path, '/var/mobile/Media/DCIM/IMG_0001.MOV');
    });

    test('maps an https URL to a network source', () {
      final source = resolveVideoSource(
        mediaUrl: 'https://example.com/clip.mp4',
        isAndroid: true,
      );

      expect(source, isNotNull);
      expect(source!.type, VideoSourceType.network);
    });

    test('returns null for a missing URL', () {
      expect(resolveVideoSource(mediaUrl: null, isAndroid: true), isNull);
      expect(resolveVideoSource(mediaUrl: '', isAndroid: true), isNull);
    });

    test('returns null for an unsupported scheme', () {
      expect(
        resolveVideoSource(mediaUrl: 'ftp://example.com/clip.mp4', isAndroid: true),
        isNull,
      );
    });
  });
}
