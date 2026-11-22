import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/controllers/gallery_controller.dart';
import 'package:gallery_image/screens/hidden_unlock_screen.dart';
import 'package:get_storage/get_storage.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GetStorage storage;

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp(
      'gallery_lock_test_',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    storage = GetStorage();
    await storage.initStorage;
  });

  testWidgets('a new lock replaces the old lock only after confirmation', (
    tester,
  ) async {
    final oldLock = {'type': 'pin4', 'salt': 'c2FsdA==', 'hash': 'old'};
    await storage.write('hidden_album_lock', oldLock);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const HiddenUnlockScreen(replaceExisting: true),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6-digit PIN').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(storage.read<Map>('hidden_album_lock'), oldLock);

    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      find.text('Entries did not match. Please start again.'),
      findsOneWidget,
    );
    expect(storage.read<Map>('hidden_album_lock'), oldLock);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && storage.read<Map>('hidden_album_lock')?['hash'] == 'old';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    final newLock = storage.read<Map>('hidden_album_lock')!;
    expect(newLock['type'], 'pin6');
    expect(
      newLock['hash'],
      deriveHiddenLock(['123456', newLock['salt'] as String]),
    );
  });

  test(
    'turning off the lock restores visible items and clears unavailable IDs',
    () async {
      final controller = GalleryController();
      final photo = AssetEntity(
        id: 'one',
        typeInt: AssetType.image.index,
        width: 1,
        height: 1,
      );
      controller.hiddenPhotos.add(photo);
      controller.favoriteIds.add(photo.id);
      await storage.write(GalleryController.hiddenKey, ['one', 'unavailable']);
      await storage.write('hidden_album_lock', {'type': 'pin4'});

      await controller.disableHiddenLock();

      expect(controller.hiddenPhotos, isEmpty);
      expect(controller.photos.map((item) => item.id), ['one']);
      expect(controller.favorites.map((item) => item.id), ['one']);
      expect(storage.read<List>(GalleryController.hiddenKey), isEmpty);
      expect(storage.read<Map>('hidden_album_lock'), isNull);
    },
  );
}
