import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/controllers/gallery_controller.dart';
import 'package:gallery_image/widgets/media_thumbnail_widget.dart';
import 'package:gallery_image/widgets/photos_tab_widget.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

class _Gallery extends GalleryController {
  @override
  Future<void> movePhotosToRecentlyDeleted(
    List<AssetEntity> selectedPhotos,
  ) async {
    final ids = selectedPhotos.map((item) => item.id).toSet();
    photos.removeWhere((item) => ids.contains(item.id));
    recentlyDeleted.addAll(selectedPhotos);
  }
}

AssetEntity _asset(String id) => AssetEntity(
  id: id,
  typeInt: AssetType.image.index,
  width: 1,
  height: 1,
  createDateSecond: 1704067200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.fluttercandies/photo_manager');
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => image);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('selects items, cancels deletion, then moves the selection', (
    tester,
  ) async {
    final gallery = _Gallery();
    gallery.permissionGranted.value = true;
    gallery.photos.assignAll([_asset('one'), _asset('two')]);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotosTab(
            controller: gallery,
            gridCount: 4.obs,
            onScaleStart: (_) {},
            onScaleUpdate: (_) {},
            onOpenPhoto: (_) => opened++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.longPress(find.byType(MediaThumbnail).first);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byType(MediaThumbnail).last);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(opened, 0);

    await tester.tap(find.text('Deselect all'));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gallery.photos.length, 2);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(gallery.photos, isEmpty);
    expect(gallery.recentlyDeleted.map((item) => item.id), ['one', 'two']);
  });
}
