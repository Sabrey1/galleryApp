
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateController extends GetxController {
  UpdateController({Future<bool> Function(Uri url)? launchUrlFn})
      : _launchUrl = launchUrlFn ?? launchUrl;

  final Future<bool> Function(Uri url) _launchUrl;

  final String versionUrl =
      'https://raw.githubusercontent.com/Sabrey1/galleryApp/main/gallery_image/version.json';

  /// Updates are installed by the user from this page in a browser.
  ///
  /// Downloading and installing an APK in-app would require the
  /// REQUEST_INSTALL_PACKAGES permission, which makes Google Play Protect
  /// classify the app as harmful and block it.
  final String releasesUrl = 'https://github.com/Sabrey1/galleryApp/releases';

  final dio = Dio();

  final isChecking = false.obs;
  final hasUpdate = false.obs;

  final currentVersion = ''.obs;
  final latestVersion = ''.obs;
  final releaseNotes = ''.obs;

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

  // Check update from GitHub
  Future<void> checkUpdate() async {
    try {
      isChecking.value = true;

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

      final version = data['version']?.toString();

      if (version == null ||
          !RegExp(r'^\d+(\.\d+){1,2}$').hasMatch(version)) {
        throw Exception('Invalid version.json fields');
      }

      // Save update information
      latestVersion.value = version;
      releaseNotes.value =
          data['release_notes']?.toString() ?? '';

      // Get current installed version
      final info = await PackageInfo.fromPlatform();
      currentVersion.value = info.version;

      // Check if update is available
      hasUpdate.value =
          isNewerVersion(version, info.version);

      if (hasUpdate.value) {
        Get.snackbar(
          'Update Available',
          'New version: $version',
        );
      } else {
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

  // Open the releases page in the browser so the user installs the update
  // themselves. Downloading and installing an APK in-app would require the
  // REQUEST_INSTALL_PACKAGES permission, which triggers Google Play Protect
  // to classify the app as harmful and block it.
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
