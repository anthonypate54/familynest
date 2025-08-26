import 'dart:io';
import 'package:flutter/material.dart';
import '../services/video_composition_service.dart';

/// Reusable widget for displaying video/photo composition preview
/// Replaces duplicated preview code across message_screen, dm_thread_screen, and thread_screen
class VideoCompositionPreview extends StatelessWidget {
  final VideoCompositionService compositionService;
  final VoidCallback onClose;
  final double? width;
  final double height;

  const VideoCompositionPreview({
    Key? key,
    required this.compositionService,
    required this.onClose,
    this.width,
    this.height = 200,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: compositionService,
      builder: (context, child) {
        if (!compositionService.hasMedia) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildMediaPreview(context),
        );
      },
    );
  }

  Widget _buildMediaPreview(BuildContext context) {
    final mediaType = compositionService.selectedMediaType!;
    final mediaFile = compositionService.selectedMediaFile!;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          SizedBox(
            width: width ?? MediaQuery.of(context).size.width * 0.7,
            height: height,
            child: _buildMediaContent(mediaType, mediaFile),
          ),
          
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.shade400,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onClose,
                  child: const Icon(
                    Icons.close,
                    color: Colors.black,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(String mediaType, File mediaFile) {
    if (mediaType == 'photo') {
      return Image.file(
        mediaFile,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else if (mediaType == 'video') {
      return _buildVideoPreview();
    }
    
    return Container(
      color: Colors.grey.shade300,
      child: const Center(
        child: Icon(Icons.error, color: Colors.red),
      ),
    );
  }

  Widget _buildVideoPreview() {
    final thumbnail = compositionService.selectedVideoThumbnail;
    final isProcessing = compositionService.isProcessingMedia;

    if (isProcessing) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Icon(
                Icons.video_library,
                color: Colors.white,
                size: 48,
              ),
              SizedBox(height: 8),
              Text(
                'Generating thumbnail...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (thumbnail != null) {
      return Stack(
        children: [
          Image.file(
            thumbnail,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
          // Play button overlay to indicate it's a video
          const Positioned.fill(
            child: Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 64,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Fallback if no thumbnail
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library,
              color: Colors.white,
              size: 48,
            ),
            SizedBox(height: 8),
            Text(
              'Video ready',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
