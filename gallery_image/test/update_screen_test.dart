// Update screen flow: Update Available dialog → user taps Update → in-app
// download with progress → "tap Install in the notification" message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gallery_image/controllers/update_controller.dart';
import 'package:gallery_image/screens/update_screen.dart';

void main() {
  UpdateController makeController({UpdaterChannel? channelFn}) {
    return UpdateController(
      launchUrlFn: (_) async => true,
      channelFn: channelFn,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    UpdateController controller,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(home: UpdateScreen(controller: controller)),
    );
    await tester.pump();
  }

  testWidgets('shows an Update Available dialog when a newer version exists',
      (tester) async {
    final controller = makeController();
    controller.latestVersion.value = '4.1.0';
    controller.releaseNotes.value = 'Bug fixes';
    controller.hasUpdate.value = true;

    await pumpScreen(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('4.1.0'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Update'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
  });

  testWidgets('shows no dialog when the app is up to date', (tester) async {
    final controller = makeController();

    await pumpScreen(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('tapping Update downloads the APK and shows the install message',
      (tester) async {
    final methods = <String>[];
    final controller = makeController(
      channelFn: (method, [args]) async {
        methods.add(method);
        if (method == 'downloadApk') return 7;
        return {'status': 'successful', 'received': 100, 'total': 100};
      },
    );
    controller.latestVersion.value = '4.1.0';
    controller.apkUrl =
        'https://github.com/Sabrey1/galleryApp/releases/download/v4.1.0/app-release.apk';
    controller.hasUpdate.value = true;

    await pumpScreen(tester, controller);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(methods, contains('downloadApk'));
    expect(find.text('Update downloaded'), findsOneWidget);
    expect(find.textContaining('notification panel'), findsOneWidget);
  });

  testWidgets('shows download progress while the APK downloads',
      (tester) async {
    final controller = makeController();
    controller.hasUpdate.value = true;
    controller.latestVersion.value = '4.1.0';
    controller.isDownloading.value = true;
    controller.progress.value = 0.45;

    await pumpScreen(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Downloading update… 45%'), findsOneWidget);
  });
}
