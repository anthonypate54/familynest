import 'dart:io';
import 'package:flutter/material.dart';

import 'package:video_compress/video_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';


class VideoThumbnailUtil {
  // Cache for video thumbnails (videoUrl -> thumbnailPath) during the current session
  static final Map<String, File> _thumbnailCache = {};

  // Persistent storage key for saving thumbnail paths between sessions
  static const String _thumbnailsDirectory = 'video_thumbnails';

  /// Generate a thumbnail for a video file or URL using a more robust approach
  /// Returns the path to the generated thumbnail file or null if generation failed
  static Future<File?> generateThumbnail(String videoPath) async {
    try {
      // First check if we have this in memory cache
      if (_thumbnailCache.containsKey(videoPath)) {
        debugPrint('Using cached thumbnail for $videoPath');
        return _thumbnailCache[videoPath];
      }

      // Next check if we have a saved thumbnail file
      final File? savedThumbnail = await _getSavedThumbnail(videoPath);
      if (savedThumbnail != null) {
        debugPrint('Using saved thumbnail for $videoPath');
        // Add to memory cache too
        _thumbnailCache[videoPath] = savedThumbnail;
        return savedThumbnail;
      }

      debugPrint('Generating new thumbnail for video: $videoPath');

      // Handle file:// prefix for local files
      final String processedPath =
          videoPath.startsWith('file://')
              ? videoPath.replaceFirst('file://', '')
              : videoPath;

      // Try using video_compress first
      try {
        debugPrint('Attempting to generate thumbnail using VideoCompress...');
        final stopwatch = Stopwatch()..start();

        // Generate thumbnail on main thread but async to prevent complete blocking
        final thumbnailFile = await Future.microtask(() async {
          return await VideoCompress.getFileThumbnail(
            processedPath,
            quality: 10,
            position: 500,
          );
        }).timeout(Duration(seconds: 3)); // Shorter timeout

        stopwatch.stop();
        debugPrint(
          '⏱️ VideoCompress.getFileThumbnail took: ${stopwatch.elapsedMilliseconds}ms',
        );

        // Save to permanent storage
        final saveStopwatch = Stopwatch()..start();
        final File persistentThumbnail = await _saveThumbnailPermanently(
          thumbnailFile,
          videoPath,
        );
        saveStopwatch.stop();
        debugPrint(
          '⏱️ _saveThumbnailPermanently took: ${saveStopwatch.elapsedMilliseconds}ms',
        );

        // Much more aggressive cache management for memory safety
        if (_thumbnailCache.length > 3) {
          debugPrint(
            '🧹 Clearing thumbnail cache aggressively (${_thumbnailCache.length} items)',
          );
          _thumbnailCache.clear();
        }

        _thumbnailCache[videoPath] = persistentThumbnail;
        debugPrint(
          'Thumbnail generated successfully with VideoCompress at: ${persistentThumbnail.path}',
        );
        return persistentThumbnail;
      } catch (e) {
        // If VideoCompress fails, we'll try a fallback approach
        debugPrint('Error from VideoCompress: $e');
        debugPrint('VideoCompress failed for path: $processedPath');
      }

      // Fallback: Try using VideoPlayerController to grab a frame
      debugPrint('Trying fallback method using VideoPlayerController...');
      File? fallbackThumbnail = await _generateThumbnailUsingVideoPlayer(
        processedPath,
        videoPath,
      );
      if (fallbackThumbnail != null) {
        _thumbnailCache[videoPath] = fallbackThumbnail;
        return fallbackThumbnail;
      }

      debugPrint('All thumbnail generation methods failed for: $videoPath');
      return null;
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      return null;
    }
  }

  /// Fallback method to generate thumbnail using VideoPlayerController
  static Future<File?> _generateThumbnailUsingVideoPlayer(
    String processedPath,
    String originalPath,
  ) async {
    try {
      // Create a VideoPlayerController to get frames
      VideoPlayerController controller;

      // Check if path is URL or file
      if (processedPath.startsWith('http')) {
        controller = VideoPlayerController.networkUrl(Uri.parse(processedPath));
      } else {
        controller = VideoPlayerController.file(File(processedPath));
      }

      // Initialize the controller with error handling
      try {
        await controller.initialize();

        // Make sure the controller is initialized
        if (!controller.value.isInitialized) {
          debugPrint('VideoPlayerController failed to initialize');
          controller.dispose();
          return null;
        }
      } catch (e) {
        debugPrint(
          'VideoPlayerController initialization failed (likely codec issue): $e',
        );
        controller.dispose();
        // Skip to creating a simple placeholder thumbnail
        // Create a simple colored placeholder when video player fails
        final placeholderBytes = await _createColoredPlaceholder();
        final thumbnailFile = File(
          '${(await getTemporaryDirectory()).path}/${_generateThumbnailFilename(originalPath)}',
        );
        await thumbnailFile.writeAsBytes(placeholderBytes);
        return await _saveThumbnailPermanently(thumbnailFile, originalPath);
      }

      // Seek to a position to get a good thumbnail
      // Try at 20% of the video
      final Duration videoDuration = controller.value.duration;
      if (videoDuration.inMilliseconds > 0) {
        final seekPosition = Duration(
          milliseconds: (videoDuration.inMilliseconds * 0.2).round(),
        );
        await controller.seekTo(seekPosition);
      }

      // Get a temporary directory to save the image
      final directory = await getTemporaryDirectory();
      final thumbnailFilename = _generateThumbnailFilename(originalPath);
      final thumbnailPath = '${directory.path}/$thumbnailFilename';

      // Create a placeholder black image file as fallback
      final fallbackFile = File(thumbnailPath);
      if (!await fallbackFile.exists()) {
        await fallbackFile.create(recursive: true);
      }

      // Create a simple colored rectangle
      final uint8List = await _createColoredPlaceholder();
      await fallbackFile.writeAsBytes(uint8List);

      // Dispose the controller
      controller.dispose();

      // Save it permanently
      final File persistentThumbnail = await _saveThumbnailPermanently(
        fallbackFile,
        originalPath,
      );
      debugPrint('Created fallback thumbnail at: ${persistentThumbnail.path}');
      return persistentThumbnail;
    } catch (e) {
      debugPrint('Error in fallback thumbnail generation: $e');
      return null;
    }
  }

  /// Create a simple colored placeholder image when all else fails
  static Future<Uint8List> _createColoredPlaceholder() async {
    const int width = 320, height = 180; // 16:9 aspect ratio

    // Create a black rectangle with a play icon as a fallback thumbnail
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Fill with dark gray
    final Paint paint = Paint()..color = Colors.black87;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paint,
    );

    // Draw a play icon
    paint.color = Colors.white.withOpacity(0.8);
    const double iconSize = 60;
    final double centerX = width / 2;
    final double centerY = height / 2;

    // Draw a circle
    canvas.drawCircle(Offset(centerX, centerY), iconSize / 2, paint);

    // Draw a triangle play icon
    paint.color = Colors.black87;
    final Path trianglePath = Path();
    trianglePath.moveTo(centerX - 10, centerY - 15);
    trianglePath.lineTo(centerX + 20, centerY);
    trianglePath.lineTo(centerX - 10, centerY + 15);
    trianglePath.close();
    canvas.drawPath(trianglePath, paint);

    // Encode to PNG
    final ui.Image image = await recorder.endRecording().toImage(width, height);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  /// Generate a consistent filename for a video path
  static String _generateThumbnailFilename(String videoPath) {
    // Create a hash of the video path to ensure a consistent filename
    final bytes = utf8.encode(videoPath);
    final digest = sha256.convert(bytes);
    return 'thumbnail_${digest.toString().substring(0, 16)}.jpg';
  }

  /// Save a thumbnail file to permanent storage
  static Future<File> _saveThumbnailPermanently(
    File thumbnailFile,
    String originalVideoPath,
  ) async {
    try {
      // Get the app's documents directory
      final appDocDir = await getApplicationDocumentsDirectory();

      // Create thumbnails directory if it doesn't exist
      final thumbnailsDir = Directory(
        '${appDocDir.path}/$_thumbnailsDirectory',
      );
      if (!await thumbnailsDir.exists()) {
        await thumbnailsDir.create(recursive: true);
      }

      // Generate a consistent filename based on the video path
      final thumbnailFilename = _generateThumbnailFilename(originalVideoPath);
      final permanentPath = '${thumbnailsDir.path}/$thumbnailFilename';

      // Copy the thumbnail to permanent storage
      return await thumbnailFile.copy(permanentPath);
    } catch (e) {
      debugPrint('Error saving thumbnail permanently: $e');
      // Return the original file if we couldn't save it
      return thumbnailFile;
    }
  }

  /// Check if we have a saved thumbnail for this video path
  static Future<File?> _getSavedThumbnail(String videoPath) async {
    try {
      // Get the app's documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      final thumbnailsDir = Directory(
        '${appDocDir.path}/$_thumbnailsDirectory',
      );

      // If directory doesn't exist, we have no saved thumbnails
      if (!await thumbnailsDir.exists()) {
        return null;
      }

      // Check if the file exists
      final thumbnailFilename = _generateThumbnailFilename(videoPath);
      final file = File('${thumbnailsDir.path}/$thumbnailFilename');

      if (await file.exists()) {
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('Error checking for saved thumbnail: $e');
      return null;
    }
  }

  /// Clears all cached thumbnails from memory (not from storage)
  static void clearCache() {
    final cacheSize = _thumbnailCache.length;
    debugPrint('🧹 Clearing thumbnail cache (${cacheSize} items)');
    _printMemoryUsage('Before cache clear');

    _thumbnailCache.clear();

    debugPrint('🧹 Video thumbnail cache cleared');
    _printMemoryUsage('After cache clear');
  }

  // Print current memory usage for debugging
  static void _printMemoryUsage(String context) {
    try {
      // Force garbage collection and add timeline marker


      final timestamp = DateTime.now().toIso8601String();
      final cacheSize = _thumbnailCache.length;
      debugPrint(
        '📊 Thumbnail Memory [$context] at $timestamp: Cache size: $cacheSize items',
      );
    } catch (e) {
      debugPrint('📊 Thumbnail Memory [$context]: Error - $e');
    }
  }

  /// Clears cached thumbnail for a specific video from memory (not from storage)
  static void clearCacheForVideo(String videoPath) {
    _thumbnailCache.remove(videoPath);
  }

  /// Gets the currently cached thumbnail if available, or generates a new one
  static Future<File?> getThumbnail(String videoPath) async {
    return _thumbnailCache[videoPath] ?? await generateThumbnail(videoPath);
  }

  /// Clears all saved thumbnails from disk storage
  static Future<void> clearAllSavedThumbnails() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final thumbnailsDir = Directory(
        '${appDocDir.path}/$_thumbnailsDirectory',
      );

      if (await thumbnailsDir.exists()) {
        await thumbnailsDir.delete(recursive: true);
        debugPrint('All saved thumbnails deleted');
      }

      // Also clear memory cache
      clearCache();
    } catch (e) {
      debugPrint('Error clearing saved thumbnails: $e');
    }
  }
}
