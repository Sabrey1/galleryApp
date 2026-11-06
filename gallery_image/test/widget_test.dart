// Smoke test: the app boots and renders the gallery shell.

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:gallery_image/main.dart';

void main() {
  testWidgets('app boots and renders the gallery shell', (tester) async {
    await tester.pumpWidget(const MyApp());
    // Let async init (GetStorage / permission request) settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GetMaterialApp), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recently Deleted'), findsOneWidget);
  });
}
