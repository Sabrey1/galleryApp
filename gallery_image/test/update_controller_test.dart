// The update flow: check version.json on GitHub, show an Update Available
// dialog, download the APK in-app through Android's DownloadManager, then
// tell the user to tap the finished-download notification to install.
//
// The releases page is only a fallback for platforms without the native
// downloader (e.g. desktop builds). REQUEST_INSTALL_PACKAGES must never
// come back — see manifest_permissions_test.dart.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/controllers/update_controller.dart';

void main() {
  // Get.context touches WidgetsBinding.instance; plain tests need the
  // binding initialized (no widget tree is pumped, so Get.context stays
  // null and in-app snackbars are skipped here).
  TestWidgetsFlutterBinding.ensureInitialized();

  const apkUrl =
      'https://github.com/Sabrey1/galleryApp/releases/download/v4.1.0/app-release.apk';

  UpdateController makeController({
    Future<bool> Function(Uri url)? launchUrlFn,
    UpdaterChannel? channelFn,
  }) {
    return UpdateController(
      launchUrlFn: launchUrlFn ?? (_) async => true,
      channelFn: channelFn,
    );
  }

  group('openReleasesPage (fallback)', () {
    test('opens the GitHub releases page in the browser', () async {
      final openedUrls = <Uri>[];
      final controller = makeController(launchUrlFn: (uri) async {
        openedUrls.add(uri);
        return true;
      });

      await controller.openReleasesPage();

      expect(openedUrls, hasLength(1));
      expect(
        openedUrls.single.toString(),
        'https://github.com/Sabrey1/galleryApp/releases',
      );
      expect(openedUrls.single.scheme, 'https');
    });

    test('releases URL is a valid absolute https URL', () {
      final controller = makeController();

      final uri = Uri.parse(controller.releasesUrl);

      expect(uri.isAbsolute, isTrue);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
    });
  });

  group('applyVersionData', () {
    test('stores version, apk url and release notes from version.json', () {
      final controller = makeController();

      controller.applyVersionData({
        'version': '4.1.0',
        'apk_url': apkUrl,
        'release_notes': 'Bug fixes',
      });

      expect(controller.latestVersion.value, '4.1.0');
      expect(controller.apkUrl, apkUrl);
      expect(controller.releaseNotes.value, 'Bug fixes');
    });

    test('rejects a non-https apk url', () {
      final controller = makeController();

      expect(
        () => controller.applyVersionData({
          'version': '4.1.0',
          'apk_url': 'http://example.com/app.apk',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing apk url', () {
      final controller = makeController();

      expect(
        () => controller.applyVersionData({'version': '4.1.0'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('downloadUpdate', () {
    test('starts the native download with the apk url', () async {
      final calls = <MapEntry<String, Map>>[];
      final controller = makeController(
        channelFn: (method, [args]) async {
          final map = args as Map;
          calls.add(MapEntry(method, map));
          if (method == 'downloadApk') return 7;
          return {'status': 'successful', 'received': 100, 'total': 100};
        },
      );
      controller.hasUpdate.value = true;
      controller.apkUrl = apkUrl;

      await controller.downloadUpdate();

      expect(calls.first.key, 'downloadApk');
      expect(calls.first.value['url'], apkUrl);
    });

    test('reports progress and marks the update as downloaded', () async {
      var polls = 0;
      final controller = makeController(
        channelFn: (method, [args]) async {
          if (method == 'downloadApk') return 7;
          polls++;
          if (polls == 1) {
            return {'status': 'running', 'received': 45, 'total': 100};
          }
          return {'status': 'successful', 'received': 100, 'total': 100};
        },
      );
      controller.hasUpdate.value = true;
      controller.apkUrl = apkUrl;

      final seen = <double>[];
      controller.progress.listen(seen.add);

      await controller.downloadUpdate();

      expect(seen, contains(0.45));
      expect(controller.progress.value, 1.0);
      expect(controller.downloadComplete.value, isTrue);
      expect(controller.isDownloading.value, isFalse);
    });

    test('does nothing when no update is available', () async {
      final calls = <String>[];
      final controller = makeController(
        channelFn: (method, [args]) async {
          calls.add(method);
          return 7;
        },
      );
      controller.hasUpdate.value = false;
      controller.apkUrl = apkUrl;

      await controller.downloadUpdate();

      expect(calls, isEmpty);
      expect(controller.isDownloading.value, isFalse);
    });

    test('does nothing when the apk url is missing', () async {
      final calls = <String>[];
      final controller = makeController(
        channelFn: (method, [args]) async {
          calls.add(method);
          return 7;
        },
      );
      controller.hasUpdate.value = true;
      controller.apkUrl = '';

      await controller.downloadUpdate();

      expect(calls, isEmpty);
    });

    test('keeps the update pending when the download fails', () async {
      final controller = makeController(
        channelFn: (method, [args]) async {
          if (method == 'downloadApk') return 7;
          return {'status': 'failed', 'received': 10, 'total': 100};
        },
      );
      controller.hasUpdate.value = true;
      controller.apkUrl = apkUrl;

      await controller.downloadUpdate();

      expect(controller.downloadComplete.value, isFalse);
      expect(controller.isDownloading.value, isFalse);
    });

    test('falls back to the releases page without a native downloader',
        () async {
      final openedUrls = <Uri>[];
      final controller = makeController(
        launchUrlFn: (uri) async {
          openedUrls.add(uri);
          return true;
        },
        channelFn: (method, [args]) async {
          throw MissingPluginException('No native downloader');
        },
      );
      controller.hasUpdate.value = true;
      controller.apkUrl = apkUrl;

      await controller.downloadUpdate();

      expect(openedUrls, hasLength(1));
      expect(openedUrls.single.toString(), controller.releasesUrl);
      expect(controller.downloadComplete.value, isFalse);
      expect(controller.isDownloading.value, isFalse);
    });
  });
}
