// The update action must open the GitHub releases page in a browser.
//
// Replaces the old flow, which downloaded an APK from a remote URL and
// launched the Android package installer. That "dropper" pattern is what
// Google Play Protect blocks as a harmful app.

import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/controllers/update_controller.dart';

void main() {
  test('update action opens the GitHub releases page in the browser', () async {
    final openedUrls = <Uri>[];

    final controller = UpdateController(
      launchUrlFn: (uri) async {
        openedUrls.add(uri);
        return true;
      },
    );

    await controller.openReleasesPage();

    expect(openedUrls, hasLength(1));
    expect(
      openedUrls.single.toString(),
      'https://github.com/Sabrey1/galleryApp/releases',
    );
    expect(openedUrls.single.scheme, 'https');
  });

  test('releases URL is a valid absolute https URL', () {
    final controller = UpdateController(launchUrlFn: (_) async => true);

    final uri = Uri.parse(controller.releasesUrl);

    expect(uri.isAbsolute, isTrue);
    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
  });
}
