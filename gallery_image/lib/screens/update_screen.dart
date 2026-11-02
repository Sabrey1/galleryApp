
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/update_controller.dart';

class UpdateScreen extends StatelessWidget {
  UpdateScreen({super.key});

  final controller = Get.put(UpdateController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Update'),
      ),
      body: Center(
        child: Obx(() => Padding(
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
                onPressed:
                    controller.isChecking.value ? null : controller.checkUpdate,
                child: controller.isChecking.value
                    ? const CircularProgressIndicator()
                    : const Text('Check Update'),
              ),

              if (controller.hasUpdate.value) ...[
                const SizedBox(height: 20),

                Text(
                  'New Version: ${controller.latestVersion.value}',
                ),

                Text(
                  controller.releaseNotes.value,
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: controller.openReleasesPage,
                  child: const Text('Update Now'),
                ),
              ],
            ],
          ),
        )),
      ),
    );
  }
}
