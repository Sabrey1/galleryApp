import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';

import '../utils/media_utils.dart';

class GalleryController extends GetxController {
  final photos = <AssetEntity>[].obs;
  final recentlyDeleted = <AssetEntity>[].obs;
  final favorites = <AssetEntity>[].obs;
  final favoriteIds = <String>{}.obs;

  final loading = false.obs;
  final permissionGranted = false.obs;

  final storage = GetStorage();

  static const String trashKey = 'recently_deleted_photo_ids';
  static const String favoritesKey = 'favorite_photo_ids';

  final Set<String> _trashIds = <String>{};

  @override
  void onInit() {
    super.onInit();
    loadPhotos();
  }

  // Save Recently Deleted IDs on the device.
  Future<void> _saveTrashIds() async {
    await storage.write(trashKey, _trashIds.toList());
  }

  Future<void> _saveFavoriteIds() async {
    await storage.write(favoritesKey, favoriteIds.toList());
  }

  // Load photos and videos from the phone.
  Future<void> loadPhotos() async {
    if (loading.value) return;

    loading.value = true;

    try {
      // Load saved Recently Deleted IDs.
      final savedIds = storage.read<List>(trashKey) ?? [];

      _trashIds
        ..clear()
        ..addAll(savedIds.map((id) => id.toString()));

      final savedFavoriteIds = storage.read<List>(favoritesKey) ?? [];
      favoriteIds
        ..clear()
        ..addAll(savedFavoriteIds.map((id) => id.toString()));

      final permission = await PhotoManager.requestPermissionExtend();

      permissionGranted.value = permission.hasAccess;

      if (!permission.hasAccess) {
        photos.clear();
        recentlyDeleted.clear();
        favorites.clear();
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: galleryRequestType,
        onlyAll: true,
      );

      if (albums.isEmpty) {
        photos.clear();
        recentlyDeleted.clear();
        favorites.clear();
        return;
      }

      final allPhotos = <AssetEntity>[];

      int page = 0;
      const pageSize = 200;

      while (true) {
        final batch = await albums.first.getAssetListPaged(
          page: page,
          size: pageSize,
        );

        allPhotos.addAll(batch);

        if (batch.length < pageSize) break;

        page++;
      }

      allPhotos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      // Separate normal photos and Recently Deleted photos.
      photos.assignAll(
        allPhotos.where((photo) => !_trashIds.contains(photo.id)),
      );

      recentlyDeleted.assignAll(
        allPhotos.where((photo) => _trashIds.contains(photo.id)),
      );

      favorites.assignAll(
        allPhotos.where(
          (photo) =>
              favoriteIds.contains(photo.id) && !_trashIds.contains(photo.id),
        ),
      );
    } catch (e) {
      // Get.snackbar('Gallery Error', e.toString());
    } finally {
      loading.value = false;
    }
  }

  // Group normal photos by date.
  Map<String, List<AssetEntity>> get groupedPhotos {
    final Map<String, List<AssetEntity>> groups = {};

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final yesterday = today.subtract(const Duration(days: 1));

    for (final photo in photos) {
      final date = photo.createDateTime;

      final photoDate = DateTime(date.year, date.month, date.day);

      String title;

      if (photoDate == today) {
        title = 'Today';
      } else if (photoDate == yesterday) {
        title = 'Yesterday';
      } else {
        title = DateFormat('MMMM yyyy').format(date);
      }

      groups.putIfAbsent(title, () => []);
      groups[title]!.add(photo);
    }

    return groups;
  }

  // Move one photo to Recently Deleted.
  Future<void> deletePhoto(AssetEntity photo) async {
    await movePhotosToRecentlyDeleted([photo]);
  }

  bool isFavorite(String photoId) => favoriteIds.contains(photoId);

  Future<void> toggleFavorite(AssetEntity photo) async {
    if (favoriteIds.remove(photo.id)) {
      favorites.removeWhere((item) => item.id == photo.id);
    } else {
      favoriteIds.add(photo.id);
      if (!_trashIds.contains(photo.id) &&
          !favorites.any((item) => item.id == photo.id)) {
        favorites.add(photo);
        favorites.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      }
    }

    await _saveFavoriteIds();
  }

  // Move multiple photos to Recently Deleted.
  Future<void> movePhotosToRecentlyDeleted(
    List<AssetEntity> selectedPhotos,
  ) async {
    if (selectedPhotos.isEmpty) return;

    for (final photo in selectedPhotos) {
      _trashIds.add(photo.id);
    }

    await _saveTrashIds();

    final selectedIds = selectedPhotos.map((photo) => photo.id).toSet();

    photos.removeWhere((photo) => selectedIds.contains(photo.id));
    favorites.removeWhere((photo) => selectedIds.contains(photo.id));

    for (final photo in selectedPhotos) {
      if (!recentlyDeleted.any((item) => item.id == photo.id)) {
        recentlyDeleted.add(photo);
      }
    }

    recentlyDeleted.sort(
      (a, b) => b.createDateTime.compareTo(a.createDateTime),
    );
  }

  // Recover one or multiple photos.
  Future<void> recoverPhotos(List<AssetEntity> selectedPhotos) async {
    if (selectedPhotos.isEmpty) return;

    final selectedIds = selectedPhotos.map((photo) => photo.id).toSet();

    for (final photo in selectedPhotos) {
      _trashIds.remove(photo.id);
    }

    await _saveTrashIds();

    recentlyDeleted.removeWhere((photo) => selectedIds.contains(photo.id));

    for (final photo in selectedPhotos) {
      if (!photos.any((item) => item.id == photo.id)) {
        photos.add(photo);
      }
      if (favoriteIds.contains(photo.id) &&
          !favorites.any((item) => item.id == photo.id)) {
        favorites.add(photo);
      }
    }

    photos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    favorites.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    // Get.snackbar('Recovered', '${selectedPhotos.length} photo(s) recovered');
  }

  // Permanently delete one or multiple photos from the phone.
  Future<void> permanentlyDeletePhotos(List<AssetEntity> selectedPhotos) async {
    if (selectedPhotos.isEmpty) return;

    try {
      final ids = selectedPhotos.map((photo) => photo.id).toList();

      final deletedIds = await PhotoManager.editor.deleteWithIds(ids);

      if (deletedIds.isEmpty) {
        // Get.snackbar('Info', 'No photos were permanently deleted');
        return;
      }

      final deletedSet = deletedIds.toSet();

      _trashIds.removeAll(deletedSet);
      favoriteIds.removeAll(deletedSet);
      await _saveTrashIds();
      await _saveFavoriteIds();

      recentlyDeleted.removeWhere((photo) => deletedSet.contains(photo.id));
      favorites.removeWhere((photo) => deletedSet.contains(photo.id));

      photos.removeWhere((photo) => deletedSet.contains(photo.id));

      Get.snackbar(
        'Deleted',
        '${deletedIds.length} item(s) permanently deleted',
      );
    } catch (e) {
      // Get.snackbar('Delete Error', e.toString());
    }
  }

  // Permanently delete everything in Recently Deleted.
  Future<void> emptyRecentlyDeleted() async {
    await permanentlyDeletePhotos(recentlyDeleted.toList());
  }
}
