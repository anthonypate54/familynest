import 'dart:io';
import 'package:flutter/material.dart';

import '../utils/video_thumbnail_util.dart';

/// Unified service for handling video composition across all screens
/// This eliminates code duplication and ensures consistent memory-safe behavior
class VideoCompositionService extends ChangeNotifier {
  // Current composition state
  File? _selectedMediaFile;
  String? _selectedMediaType;
  File? _selectedVideoThumbnail;
  bool _isProcessingMedia = false;

  // Getters for current state
  File? get selectedMediaFile => _selectedMediaFile;
  String? get selectedMediaType => _selectedMediaType;
  File? get selectedVideoThumbnail => _selectedVideoThumbnail;
  bool get isProcessingMedia => _isProcessingMedia;

  // Check if we have any media selected
  bool get hasMedia => _selectedMediaFile != null;
  bool get hasVideo => _selectedMediaType == 'video';
  bool get hasPhoto => _selectedMediaType == 'photo';

  /// Process a local file for composition (photo or video)
  /// Uses memory-safe approach - no video controllers during composition
  Future<bool> processLocalFile(File file, String type) async {
    // Prevent multiple simultaneous processing
    if (_isProcessingMedia) {
      debugPrint(
        'Already processing media, ignoring duplicate request',
      );
      return false;
    }

    debugPrint(
      'Starting media processing for $type',
    );
    _isProcessingMedia = true;
    notifyListeners();

    try {
      // Clear previous state
      await clearComposition();

      if (type == 'video') {
        // Generate thumbnail with memory management
        debugPrint(
          'VideoCompositionService: Generating thumbnail for video: ${file.path}',
        );

        try {
          final File? thumbnailFile =
              await VideoThumbnailUtil.generateThumbnail('file://${file.path}');
          _selectedVideoThumbnail = thumbnailFile;
          debugPrint(
            'Thumbnail generated successfully',
          );
        } catch (e) {
          debugPrint(
            'Thumbnail generation failed: $e',
          );
          _selectedVideoThumbnail = null;
        }

        // MEMORY-SAFE: Skip video controller initialization to prevent OOM crashes
        debugPrint(
          'VideoCompositionService: Skipping video player initialization to prevent OOM crash',
        );
        debugPrint(
          '📸 VideoCompositionService: Will show thumbnail-only preview',
        );

        debugPrint(
          'Video ready for upload (thumbnail-only preview)',
        );
      }

      // Set the selected media
      _selectedMediaFile = file;
      _selectedMediaType = type;

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error processing media file: $e');
      return false;
    } finally {
      _isProcessingMedia = false;
      notifyListeners();
    }
  }

  /// Clear current composition and free resources
  Future<void> clearComposition() async {
    // Clear thumbnail cache
    VideoThumbnailUtil.clearCache();

    // Clear state
    _selectedMediaFile = null;
    _selectedMediaType = null;
    _selectedVideoThumbnail = null;
    _isProcessingMedia = false; // Ensure processing state is reset

    debugPrint(
      'VideoCompositionService: Cleared composition, isProcessingMedia = false',
    );
    notifyListeners();
  }

  /// Get the file info for the currently selected media
  Map<String, dynamic>? getSelectedMediaInfo() {
    if (_selectedMediaFile == null) return null;

    return {
      'file': _selectedMediaFile!,
      'type': _selectedMediaType!,
      'hasVideo': hasVideo,
      'hasPhoto': hasPhoto,
      'thumbnail': _selectedVideoThumbnail,
      'fileName': _selectedMediaFile!.path.split('/').last,
    };
  }

  /// Validate file before processing
  bool validateFile(File file, String type) {
    if (!file.existsSync()) {
      debugPrint(
        'File does not exist: ${file.path}',
      );
      return false;
    }

    final sizeInMB = file.lengthSync() / (1024 * 1024);

    if (type == 'video') {
      if (sizeInMB > 100) {
        // 100MB limit for videos
        debugPrint(
          'Video file too large: ${sizeInMB.toStringAsFixed(1)}MB',
        );
        return false;
      }
    } else if (type == 'photo') {
      if (sizeInMB > 50) {
        // 50MB limit for photos
        debugPrint(
          'Photo file too large: ${sizeInMB.toStringAsFixed(1)}MB',
        );
        return false;
      }
    }

    debugPrint(
      'File validated - ${sizeInMB.toStringAsFixed(1)}MB',
    );
    return true;
  }

  @override
  void dispose() {
    clearComposition();
    super.dispose();
  }
}
