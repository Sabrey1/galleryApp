
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/update_controller.dart';

class UpdateScreen extends StatelessWidget {
  UpdateScreen({super.key, UpdateController? controller})
      : controller = controller ?? Get.put(UpdateController());

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Update'),
      ),
      body: Center(
        child: Obx(() {
          // A newer version exists: raise the Update Available dialog once
          // per check.
          if (controller.hasUpdate.value &&
              !controller.isChecking.value &&
              !controller.updateDialogShown) {
            controller.updateDialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Get.dialog<void>(UpdateAvailableDialog(controller: controller));
            });
          }

          // The APK finished downloading: tell the user to tap the
          // finished-download notification, which opens Android's installer.
          if (controller.downloadComplete.value &&
              !controller.readyDialogShown) {
            controller.readyDialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Get.dialog<void>(const UpdateReadyDialog());
            });
          }

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.system_update,
                  size: 70,
                ),

                const SizedBox(height: 20),

                Text(
                  'Current Version: ${controller.currentVersion.value}',
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: controller.isChecking.value
                      ? null
                      : () {
                          controller.updateDialogShown = false;
                          controller.checkUpdate();
                        },
                  child: controller.isChecking.value
                      ? const CircularProgressIndicator()
                      : const Text('Check Update'),
                ),

                if (controller.hasUpdate.value &&
                    !controller.isChecking.value) ...[
                  const SizedBox(height: 20),

                  Text(
                    'New Version: ${controller.latestVersion.value}',
                  ),

                  if (controller.releaseNotes.value.isNotEmpty)
                    Text(
                      controller.releaseNotes.value,
                    ),

                  const SizedBox(height: 20),

                  if (controller.isDownloading.value) ...[
                    LinearProgressIndicator(
                      value: controller.progress.value,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Downloading update… ${(controller.progress.value * 100).round()}%',
                    ),

                    const SizedBox(height: 20),
                  ],

                  ElevatedButton(
                    onPressed: controller.isDownloading.value ||
                            controller.downloadComplete.value
                        ? null
                        : controller.downloadUpdate,
                    child: const Text('Update Now'),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Dialog shown when version.json reports a newer version than the
/// installed one. "Update" starts the in-app APK download.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final notes = controller.releaseNotes.value;
    final headline =
        'A new version (${controller.latestVersion.value}) is available.';

    return AlertDialog(
      title: const Text('Update Available'),
      content: Text(
        notes.isEmpty ? headline : '$headline\n\n$notes',
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () {
            Get.back();
            controller.downloadUpdate();
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}

/// Dialog shown once the APK download finishes. The Android installer opens
/// when the user taps the finished-download notification, and the user
/// confirms the installation there.
class UpdateReadyDialog extends StatelessWidget {
  const UpdateReadyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update downloaded'),
      content: const Text(
        'Tap Install in the notification panel to install the update.\n\n'
        'The app will restart into the new version.',
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
