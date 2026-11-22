import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/main.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp(
      'gallery_theme_test_',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    await GetStorage.init();
  });

  testWidgets('switches appearance, remembers it, and follows the system', (
    tester,
  ) async {
    await GetStorage().remove('theme_mode');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(Get.reset);

    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(
      Theme.of(tester.element(find.text('Gallery'))).brightness,
      Brightness.light,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Hidden album'), findsOneWidget);
    expect(find.text('App Update'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Theme.of(tester.element(find.text('Gallery'))).brightness,
      Brightness.dark,
    );
    expect(GetStorage().read<String>('theme_mode'), 'dark');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(
      Theme.of(tester.element(find.text('Gallery'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Theme.of(tester.element(find.text('Gallery'))).brightness,
      Brightness.light,
    );
    expect(GetStorage().read<String>('theme_mode'), 'light');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('System default'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Theme.of(tester.element(find.text('Gallery'))).brightness,
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Theme.of(tester.element(find.text('Gallery'))).brightness,
      Brightness.dark,
    );
    expect(GetStorage().read<String>('theme_mode'), 'system');

    PackageInfo.setMockInitialValues(
      appName: 'Gallery',
      packageName: 'example.gallery',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('App Update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Check Update'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Hidden album'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Set up hidden album'), findsOneWidget);
  });
}
