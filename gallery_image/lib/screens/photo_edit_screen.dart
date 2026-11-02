
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image/image.dart' as img;

class PhotoEditScreen extends StatefulWidget {
  final AssetEntity photo;

  const PhotoEditScreen({
    super.key,
    required this.photo,
  });

  @override
  State<PhotoEditScreen> createState() =>
      _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen> {
  final CropController cropController = CropController();

  Uint8List? imageBytes;

  bool loading = true;
  bool saving = false;
  bool cropMode = false;

  String selectedFilter = 'Original';

  final List<String> filters = [
    'Original',
    'B&W',
    'Sepia',
    'Vivid',
  ];

  @override
  void initState() {
    super.initState();
    loadImage();
  }

  // Load original photo from phone gallery.
  Future<void> loadImage() async {
    try {
      Uint8List? bytes = await widget.photo.originBytes;

      if (bytes == null || img.decodeImage(bytes) == null) {
        final file = await widget.photo.file;

        if (file != null) {
          bytes = await file.readAsBytes();
        }
      }

      if (!mounted) return;

      setState(() {
        imageBytes = bytes;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot load image: $e'),
        ),
      );
    }
  }

  // Rotate photo 90 degrees clockwise.
  Future<void> rotateImage() async {
    if (imageBytes == null) return;

    final decoded = img.decodeImage(imageBytes!);

    if (decoded == null) return;

    final rotated = img.copyRotate(
      decoded,
      angle: 90,
    );

    setState(() {
      imageBytes = Uint8List.fromList(
        img.encodeJpg(rotated, quality: 95),
      );

      selectedFilter = 'Original';
    });
  }

  // Select filter.
  void selectFilter(String filter) {
    setState(() {
      selectedFilter = filter;
    });
  }

  // Preview filter.
  ColorFilter getPreviewFilter() {
    switch (selectedFilter) {
      case 'B&W':
        return const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);

      case 'Sepia':
        return const ColorFilter.matrix([
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]);

      case 'Vivid':
        return const ColorFilter.matrix([
          1.2, 0, 0, 0, 0,
          0, 1.2, 0, 0, 0,
          0, 0, 1.2, 0, 0,
          0, 0, 0, 1, 0,
        ]);

      default:
        return const ColorFilter.mode(
          Colors.transparent,
          BlendMode.dst,
        );
    }
  }

  // Apply selected filter to actual image data.
  Uint8List applySelectedFilter(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);

    if (decoded == null) {
      throw Exception('Unsupported image format');
    }

    switch (selectedFilter) {
      case 'B&W':
        img.grayscale(decoded);
        break;

      case 'Sepia':
        img.sepia(decoded);
        break;

      case 'Vivid':
        img.adjustColor(
          decoded,
          saturation: 1.4,
          contrast: 1.1,
        );
        break;
    }

    return Uint8List.fromList(
      img.encodeJpg(decoded, quality: 95),
    );
  }

  // Save edited photo as a new photo in phone gallery.
  Future<void> saveImage() async {
    if (imageBytes == null || saving) return;

    setState(() {
      saving = true;
    });

    try {
      final editedBytes = applySelectedFilter(imageBytes!);

      final filename =
          'edited_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final savedPhoto = await PhotoManager.editor.saveImage(
        editedBytes,
        filename: filename,
        title: filename,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Edited photo saved to gallery'),
        ),
      );

      Navigator.pop(context, savedPhoto);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save error: $e'),
        ),
      );
    }
  }

  // Handle crop result.
  void onCropped(CropResult result) {
    if (result is CropSuccess) {
      setState(() {
        imageBytes = result.croppedImage;
        cropMode = false;
        selectedFilter = 'Original';
      });
    } else if (result is CropFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Crop error: ${result.cause}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          cropMode ? 'Crop photo' : 'Edit photo',
        ),
        actions: [
          if (!cropMode)
            TextButton(
              onPressed: saving || loading ? null : saveImage,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
            ),
        ],
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : imageBytes == null
              ? const Center(
                  child: Text(
                    'Cannot load this photo',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: cropMode
                          ? Crop(
                              image: imageBytes!,
                              controller: cropController,
                              onCropped: onCropped,
                              baseColor: Colors.black,
                              maskColor: Colors.black.withAlpha(150),
                              interactive: true,
                            )
                          : Center(
                              child: InteractiveViewer(
                                child: ColorFiltered(
                                  colorFilter: getPreviewFilter(),
                                  child: Image.memory(
                                    imageBytes!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                    ),

                    if (cropMode)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    cropMode = false;
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  cropController.crop();
                                },
                                child: const Text('Apply Crop'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      editorToolbar(),
                  ],
                ),
    );
  }

  // Editor toolbar.
  Widget editorToolbar() {
    return Container(
      color: const Color(0xFF171717),
      padding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 12,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                editorButton(
                  icon: Icons.rotate_right,
                  label: 'Rotate',
                  onTap: rotateImage,
                ),
                editorButton(
                  icon: Icons.crop,
                  label: 'Crop',
                  onTap: () {
                    setState(() {
                      cropMode = true;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Filters',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              height: 45,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filters.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = filters[index];

                  return ChoiceChip(
                    label: Text(filter),
                    selected: selectedFilter == filter,
                    onSelected: (_) => selectFilter(filter),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget editorButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 8,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
