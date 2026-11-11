import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/update_controller.dart';

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
      content: Text(notes.isEmpty ? headline : '$headline\n\n$notes'),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Later')),
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
