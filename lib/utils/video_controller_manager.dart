import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

/// Singleton manager to prevent ExoPlayer resource conflicts
class VideoControllerManager extends ChangeNotifier {
  static final VideoControllerManager _instance =
      VideoControllerManager._internal();
  factory VideoControllerManager() => _instance;
  VideoControllerManager._internal();

  String? _currentPlayingVideoUrl;
  VideoPlayerController? _globalController;
  ChewieController? _globalChewieController;

  /// Check if a specific video URL should be playing
  bool isVideoPlaying(String videoUrl) {
    return _currentPlayingVideoUrl == videoUrl;
  }

  /// Set which video should be playing (stops others)
  void setPlayingVideo(String videoUrl) {
    if (_currentPlayingVideoUrl != videoUrl) {
      _currentPlayingVideoUrl = videoUrl;
      debugPrint('▶️ Now playing video: $videoUrl');
      notifyListeners(); // This will tell other video cards to stop
    }
  }

  /// Stop all videos
  void stopAllVideos() {
    _currentPlayingVideoUrl = null;
    debugPrint('⏹️ All videos stopped');
    notifyListeners();
  }

  /// Get or create a video controller (singleton pattern)
  Future<VideoPlayerController?> getController(
    String videoPath, {
    String? localPath,
  }) async {
    // Dispose previous controller to prevent resource leaks
    await _disposeGlobalController();

    try {
      debugPrint('🎬 Creating new global video controller');
      debugPrint(
        '🔍 Input paths: videoPath="$videoPath", localPath="$localPath"',
      );

      // Determine which path to use
      String finalPath = videoPath;
      if (localPath != null && localPath.isNotEmpty) {
        final localFile = File(localPath);
        final exists = await localFile.exists();
        final fileSize = exists ? await localFile.length() : 0;

        debugPrint(
          '🔍 Local file check: exists=$exists, size=$fileSize bytes, path=$localPath',
        );

        if (exists && fileSize > 0) {
          finalPath = localPath;
          debugPrint('✅ Using local file: $finalPath (${fileSize} bytes)');
        } else {
          debugPrint(
            '⚠️ Local file not ready (exists=$exists, size=$fileSize), using network: $videoPath',
          );
        }
      } else {
        debugPrint('⚠️ No local path provided, using network: $videoPath');
      }

      // Create controller
      if (finalPath.startsWith('file://') || finalPath.startsWith('/')) {
        _globalController = VideoPlayerController.file(
          File(finalPath.replaceFirst('file://', '')),
        );
      } else {
        _globalController = VideoPlayerController.networkUrl(
          Uri.parse(finalPath),
        );
      }

      await _globalController!.initialize();
      debugPrint('✅ Global video controller initialized');

      return _globalController;
    } catch (e) {
      debugPrint('❌ Error creating global video controller: $e');
      await _disposeGlobalController();
      return null;
    }
  }

  /// Create Chewie controller
  ChewieController? createChewieController(
    VideoPlayerController videoController,
  ) {
    _globalChewieController?.dispose();

    _globalChewieController = ChewieController(
      videoPlayerController: videoController,
      autoPlay: false,
      looping: false,
      showControls: false,
      allowFullScreen: false,
      allowMuting: false,
      showControlsOnInitialize: false,
    );

    return _globalChewieController;
  }

  /// Dispose global controllers
  Future<void> _disposeGlobalController() async {
    if (_globalChewieController != null) {
      debugPrint('🧹 Disposing global Chewie controller');
      _globalChewieController!.dispose();
      _globalChewieController = null;
    }

    if (_globalController != null) {
      debugPrint('🧹 Disposing global video controller');
      _globalController!.dispose();
      _globalController = null;
    }
  }

  /// Force cleanup of all resources
  Future<void> forceCleanup() async {
    debugPrint('🧹 Force cleanup of all video resources');
    await _disposeGlobalController();
    _currentPlayingVideoUrl = null;
    notifyListeners();
  }

  /// Reset singleton instance (for development/debugging)
  static void resetInstance() {
    debugPrint('🔄 Resetting VideoControllerManager singleton');
    _instance._disposeGlobalController();
    _instance._currentPlayingVideoUrl = null;
  }
}
