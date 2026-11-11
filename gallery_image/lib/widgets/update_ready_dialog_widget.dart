import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
        TextButton(onPressed: () => Get.back(), child: const Text('OK')),
      ],
    );
  }
}
