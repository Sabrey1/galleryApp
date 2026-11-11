import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/update_controller.dart';
import '../widgets/update_available_dialog_widget.dart';
import '../widgets/update_ready_dialog_widget.dart';

export '../widgets/update_available_dialog_widget.dart';
export '../widgets/update_ready_dialog_widget.dart';

class UpdateScreen extends StatelessWidget {
  UpdateScreen({super.key, UpdateController? controller})
    : controller = controller ?? Get.put(UpdateController());

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Update')),
      body: Center(
        child: Obx(() {
        
          if (controller.hasUpdate.value &&
              !controller.isChecking.value &&
              !controller.updateDialogShown) {
            controller.updateDialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Get.dialog<void>(UpdateAvailableDialog(controller: controller));
            });
          }

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
                const Icon(Icons.system_update, size: 70),

                const SizedBox(height: 20),

                Text('Current Version: ${controller.currentVersion.value}'),

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

                  Text('New Version: ${controller.latestVersion.value}'),

                  if (controller.releaseNotes.value.isNotEmpty)
                    Text(controller.releaseNotes.value),

                  const SizedBox(height: 20),

                  if (controller.isDownloading.value) ...[
                    LinearProgressIndicator(value: controller.progress.value),

                    const SizedBox(height: 8),

                    Text(
                      'Downloading update… ${(controller.progress.value * 100).round()}%',
                    ),

                    const SizedBox(height: 20),
                  ],

                  ElevatedButton(
                    onPressed:
                        controller.isDownloading.value ||
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
