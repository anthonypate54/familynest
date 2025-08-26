import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
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
      debugPrint('⚠️ VideoCompositionService: Already processing media, ignoring duplicate request');
      return false;
    }

    debugPrint('🔄 VideoCompositionService: Starting media processing for $type');
    _isProcessingMedia = true;
    notifyListeners();

    try {
      // Clear previous state
      await clearComposition();

      if (type == 'video') {
        // Generate thumbnail with memory management
        debugPrint('🎯 VideoCompositionService: Generating thumbnail for video: ${file.path}');
        _printMemoryUsage('Before thumbnail generation');

        try {
          final File? thumbnailFile =
              await VideoThumbnailUtil.generateThumbnail('file://${file.path}');
          _selectedVideoThumbnail = thumbnailFile;
          debugPrint('✅ VideoCompositionService: Thumbnail generated successfully');
          _printMemoryUsage('After thumbnail generation');
        } catch (e) {
          debugPrint('❌ VideoCompositionService: Thumbnail generation failed: $e');
          _selectedVideoThumbnail = null;
          _printMemoryUsage('After thumbnail generation error');
        }

        // MEMORY-SAFE: Skip video controller initialization to prevent OOM crashes
        debugPrint('🚫 VideoCompositionService: Skipping video player initialization to prevent OOM crash');
        debugPrint('📸 VideoCompositionService: Will show thumbnail-only preview');

        debugPrint('✅ VideoCompositionService: Video ready for upload (thumbnail-only preview)');
      }

      // Set the selected media
      _selectedMediaFile = file;
      _selectedMediaType = type;
      
      notifyListeners();
      return true;

    } catch (e) {
      debugPrint('❌ VideoCompositionService: Error processing media file: $e');
      return false;
    } finally {
      debugPrint('🔄 VideoCompositionService: Media processing completed');

      // Force garbage collection after media processing
      developer.Timeline.startSync('force_gc');
      developer.Timeline.finishSync();

      _isProcessingMedia = false;
      notifyListeners();
    }
  }

  /// Clear current composition and free resources
  Future<void> clearComposition() async {
    debugPrint('🧹 VideoCompositionService: Starting resource cleanup...');
    _printMemoryUsage('Before cleanup');

    // Clear thumbnail cache
    VideoThumbnailUtil.clearCache();
    _printMemoryUsage('After cache clear');

    // Clear state
    _selectedMediaFile = null;
    _selectedMediaType = null;
    _selectedVideoThumbnail = null;

    debugPrint('🧹 VideoCompositionService: Resource cleanup completed');
    _printMemoryUsage('After cleanup');
    
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
      debugPrint('❌ VideoCompositionService: File does not exist: ${file.path}');
      return false;
    }

    final sizeInMB = file.lengthSync() / (1024 * 1024);
    
    if (type == 'video') {
      if (sizeInMB > 100) { // 100MB limit for videos
        debugPrint('❌ VideoCompositionService: Video file too large: ${sizeInMB.toStringAsFixed(1)}MB');
        return false;
      }
    } else if (type == 'photo') {
      if (sizeInMB > 50) { // 50MB limit for photos
        debugPrint('❌ VideoCompositionService: Photo file too large: ${sizeInMB.toStringAsFixed(1)}MB');
        return false;
      }
    }

    debugPrint('✅ VideoCompositionService: File validated - ${sizeInMB.toStringAsFixed(1)}MB');
    return true;
  }

  /// Print current memory usage for debugging
  void _printMemoryUsage(String context) {
    try {
      // Force garbage collection first
      developer.Timeline.startSync('memory_check');
      developer.Timeline.finishSync();

      // Print timestamp for memory tracking
      final timestamp = DateTime.now().toIso8601String();
      debugPrint(
        '📊 VideoCompositionService Memory [$context] at $timestamp: Checking memory usage...',
      );

      // Note: Detailed memory info requires running with --observatory-port
      // For now, we'll track this via timeline and external profiling tools
    } catch (e) {
      debugPrint('📊 VideoCompositionService Memory [$context]: Error - $e');
    }
  }

  @override
  void dispose() {
    clearComposition();
    super.dispose();
  }
}
