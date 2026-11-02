
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class UpdateController extends GetxController {
  // Your GitHub version.json
  final String versionUrl =
    'https://raw.githubusercontent.com/Sabrey1/galleryApp/main/gallery_image/version.json';

  final dio = Dio();

  final isChecking = false.obs;
  final isDownloading = false.obs;
  final hasUpdate = false.obs;
  final progress = 0.0.obs;

  final currentVersion = ''.obs;
  final latestVersion = ''.obs;
  final releaseNotes = ''.obs;

  String apkUrl = '';

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
    List<int> a = latest.split('.').map(int.parse).toList();
    List<int> b = current.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;

      if (x > y) return true;
      if (x < y) return false;
    }

    return false;
  }

  // Check update from GitHub
  Future<void> checkUpdate() async {
    try {
      isChecking.value = true;
      hasUpdate.value = false;

      await getCurrentVersion();

      final response = await dio.get(
        versionUrl,
        options: Options(
          responseType: ResponseType.json,
        ),
      );

      final data = response.data;

      if (data is! Map) {
        throw Exception('Invalid version.json');
      }

      latestVersion.value = data['version']?.toString() ?? '';
      apkUrl = data['apk_url']?.toString() ?? '';
      releaseNotes.value =
          data['release_notes']?.toString() ?? '';

      if (latestVersion.value.isEmpty || apkUrl.isEmpty) {
        throw Exception('Version information is incomplete');
      }

      hasUpdate.value = isNewerVersion(
        latestVersion.value,
        currentVersion.value,
      );

      if (hasUpdate.value) {
        Get.snackbar(
          'Update Available',
          'New version ${latestVersion.value} is available!',
        );
      } else {
        Get.snackbar(
          'Update',
          'Your app is already up to date!',
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

  // Download and install APK
  Future<void> downloadUpdate() async {
    if (apkUrl.isEmpty) return;

    try {
      isDownloading.value = true;
      progress.value = 0;

      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/app-update.apk';

      await dio.download(
        apkUrl,
        apkPath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress.value = received / total;
          }
        },
      );

      isDownloading.value = false;

      // Open Android APK installer
      await OpenFilex.open(apkPath);

    } catch (e) {
      Get.snackbar(
        'Download Error',
        'Could not download or open APK: $e',
      );
    } finally {
      isDownloading.value = false;
    }
  }
}
