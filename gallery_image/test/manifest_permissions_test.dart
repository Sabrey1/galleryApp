// Regression guard for Google Play Protect "Harmful app blocked".
//
// Declaring REQUEST_INSTALL_PACKAGES while also downloading + installing an
// APK makes Play Protect classify the app as a dropper (Potentially Harmful
// Application). The self-update flow now opens the releases page in a browser
// instead, so this permission must never come back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';

  test('manifest does not declare REQUEST_INSTALL_PACKAGES', () {
    final manifest = File(manifestPath).readAsStringSync();

    expect(
      manifest,
      isNot(contains('REQUEST_INSTALL_PACKAGES')),
      reason:
          'REQUEST_INSTALL_PACKAGES is a high-risk permission. Holding it '
          'while downloading APKs triggers Google Play Protect to block the '
          'app as harmful. Use the browser instead of an in-app installer.',
    );
  });
}
