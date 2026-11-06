
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Platform bridge for in-app downloads.
///
/// `downloadApk` enqueues the APK on Android's DownloadManager and returns
/// its id; `getProgress` reports `{status, received, total}` for that id.
typedef UpdaterChannel = Future<dynamic> Function(
  String method, [
  dynamic arguments,
]);

Future<dynamic> _defaultUpdaterChannel(
  String method, [
  dynamic arguments,
]) {
  return const MethodChannel('gallery_image/updater')
      .invokeMethod<dynamic>(method, arguments);
}

class UpdateController extends GetxController {
  UpdateController({
    Future<bool> Function(Uri url)? launchUrlFn,
    UpdaterChannel? channelFn,
  })  : _launchUrl = launchUrlFn ?? launchUrl,
        _channel = channelFn ?? _defaultUpdaterChannel;

  final Future<bool> Function(Uri url) _launchUrl;
  final UpdaterChannel _channel;

  final String versionUrl =
      'https://raw.githubusercontent.com/Sabrey1/galleryApp/main/gallery_image/version.json';

  /// Fallback for platforms without the native downloader.
  ///
  /// The APK itself is downloaded in-app through Android's DownloadManager,
  /// which needs no extra permission. The app must never declare
  /// REQUEST_INSTALL_PACKAGES: together with downloading APKs it makes
  /// Google Play Protect classify the app as a dropper and block it.
  final String releasesUrl = 'https://github.com/Sabrey1/galleryApp/releases';

  final dio = Dio();

  final isChecking = false.obs;
  final isDownloading = false.obs;
  final hasUpdate = false.obs;
  final progress = 0.0.obs;
  final downloadComplete = false.obs;

  final currentVersion = ''.obs;
  final latestVersion = ''.obs;
  final releaseNotes = ''.obs;

  /// Direct https URL of the APK for [latestVersion], read from version.json.
  String apkUrl = '';

  /// One-shot guards so each dialog appears once per check / download.
  bool updateDialogShown = false;
  bool readyDialogShown = false;

  @override
  void onInit() {
    super.onInit();
    getCurrentVersion();
  }

  // Get installed app version
  Future<void> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    currentVersion.value = info.version;
  }

  // Compare versions
  bool isNewerVersion(String latest, String current) {
    try {
      final a = latest.split('.').map(int.parse).toList();
      final b = current.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final x = i < a.length ? a[i] : 0;
        final y = i < b.length ? b[i] : 0;

        if (x > y) return true;
        if (x < y) return false;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Validates version.json [data] and stores it for the update flow.
  ///
  /// Throws [FormatException] when the payload cannot drive an in-app
  /// update: the version must be numeric and the apk url must be an
  /// absolute https URL.
  void applyVersionData(Map<String, dynamic> data) {
    final version = data['version']?.toString();
    final url = data['apk_url']?.toString();
    final uri = url == null ? null : Uri.tryParse(url);

    if (version == null ||
        url == null ||
        !RegExp(r'^\d+(\.\d+){1,2}$').hasMatch(version) ||
        uri == null ||
        !uri.isAbsolute ||
        uri.scheme != 'https') {
      throw const FormatException('Invalid version.json fields');
    }

    latestVersion.value = version;
    apkUrl = url;
    releaseNotes.value = data['release_notes']?.toString() ?? '';
  }

  // Check update from GitHub
  Future<void> checkUpdate() async {
    try {
      isChecking.value = true;
      updateDialogShown = false;

      final response = await dio.get(
        versionUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      // Decode JSON
      final String responseText = response.data.toString();
      final data = jsonDecode(responseText);

      if (data is! Map<String, dynamic>) {
        throw Exception('Invalid JSON format');
      }

      applyVersionData(data);

      // Get current installed version
      final info = await PackageInfo.fromPlatform();
      currentVersion.value = info.version;

      // Check if update is available
      hasUpdate.value =
          isNewerVersion(latestVersion.value, info.version);

      // When an update exists the UpdateScreen raises the Update Available
      // dialog; only report the up-to-date case here.
      if (!hasUpdate.value) {
        Get.snackbar(
          'No Update',
          'Your app is already up to date.',
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Cannot check for updates: $e',
      );
    } finally {
      isChecking.value = false;
    }
  }

  /// Downloads the APK through the platform downloader (Android
  /// DownloadManager) and reports live progress.
  ///
  /// When the download finishes, [downloadComplete] turns true so the
  /// screen can tell the user to tap the finished-download notification,
  /// which opens Android's installer. On platforms without the native
  /// downloader (e.g. desktop builds) it falls back to the releases page.
  Future<void> downloadUpdate() async {
    if (!hasUpdate.value || apkUrl.isEmpty || isDownloading.value) return;

    try {
      isDownloading.value = true;
      downloadComplete.value = false;
      readyDialogShown = false;
      progress.value = 0;

      final dynamic id = await _channel('downloadApk', {
        'url': apkUrl,
        'fileName': 'gallery-update-${latestVersion.value}.apk',
      });

      var polls = 0;
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final dynamic state = await _channel('getProgress', {'id': id});
        if (state is! Map) {
          throw Exception('Download not found');
        }

        final status = state['status']?.toString();
        final total = (state['total'] as num?)?.toInt() ?? 0;
        final received = (state['received'] as num?)?.toInt() ?? 0;
        if (total > 0) {
          progress.value = (received / total).clamp(0.0, 1.0).toDouble();
        }

        if (status == 'successful') {
          progress.value = 1;
          downloadComplete.value = true;
          break;
        }
        if (status == 'failed') {
          throw Exception('The download failed');
        }
        if (++polls >= 2000) {
          throw Exception('The download timed out');
        }
      }
    } on MissingPluginException {
      // No native downloader on this platform: open the releases page.
      await openReleasesPage();
    } catch (e) {
      if (Get.context != null) {
        Get.snackbar(
          'Download Error',
          'Could not download update: $e',
        );
      }
    } finally {
      isDownloading.value = false;
    }
  }

  // Open the releases page in the browser. Used only as a fallback when
  // the native downloader is unavailable (e.g. desktop builds).
  Future<void> openReleasesPage() async {
    try {
      final opened = await _launchUrl(Uri.parse(releasesUrl));

      if (!opened) {
        Get.snackbar(
          'Error',
          'Could not open the updates page.',
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Could not open the updates page: $e',
      );
    }
  }
}
