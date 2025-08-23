import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PhotoViewer extends StatelessWidget {
  final String imageUrl;
  final String? heroTag;
  final String? title;

  const PhotoViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.title,
  });

  static void show({
    required BuildContext context,
    required String imageUrl,
    String? heroTag,
    String? title,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                PhotoViewer(imageUrl: imageUrl, heroTag: heroTag, title: title),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: title != null ? Text(title!) : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: CachedNetworkImageProvider(imageUrl),
        heroAttributes:
            heroTag != null ? PhotoViewHeroAttributes(tag: heroTag!) : null,
        minScale: PhotoViewComputedScale.contained * 0.8,
        maxScale: PhotoViewComputedScale.covered * 3.0,
        initialScale: PhotoViewComputedScale.contained,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 16),
                  if (event != null)
                    Text(
                      '${((event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1)) * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.white, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Failed to load image',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
