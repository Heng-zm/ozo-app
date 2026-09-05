import 'dart:io';
import 'package:flutter/material.dart';

/// Full-screen interactive lightbox viewer with pinch-to-zoom and panning
class MediaGalleryViewer extends StatelessWidget {
  final File imageFile;
  final String fileName;
  final String? subtitle;

  const MediaGalleryViewer({
    super.key,
    required this.imageFile,
    required this.fileName,
    this.subtitle,
  });

  static void show(
    BuildContext context, {
    required File imageFile,
    required String fileName,
    String? subtitle,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withAlpha(230),
        pageBuilder: (context, animation, secondaryAnimation) => MediaGalleryViewer(
          imageFile: imageFile,
          fileName: fileName,
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.black.withAlpha(180),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          clipBehavior: Clip.none,
          child: Image.file(
            imageFile,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
                const SizedBox(height: 12),
                Text(
                  'Could not display image: $error',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
