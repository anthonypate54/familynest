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
      notifyListeners(); // This will tell other video cards to stop
    }
  }

  /// Stop all videos
  void stopAllVideos() {
    _currentPlayingVideoUrl = null;
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
      // Determine which path to use
      String finalPath = videoPath;
      if (localPath != null && localPath.isNotEmpty) {
        final localFile = File(localPath);
        final exists = await localFile.exists();
        final fileSize = exists ? await localFile.length() : 0;

        if (exists && fileSize > 0) {
          finalPath = localPath;
        }
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
      return _globalController;
    } catch (e) {
      debugPrint('Error creating video controller: $e');
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
      _globalChewieController!.dispose();
      _globalChewieController = null;
    }

    if (_globalController != null) {
      _globalController!.dispose();
      _globalController = null;
    }
  }

  /// Force cleanup of all resources
  Future<void> forceCleanup() async {
    await _disposeGlobalController();
    _currentPlayingVideoUrl = null;
    notifyListeners();
  }

  /// Reset singleton instance (for development/debugging)
  static void resetInstance() {
    _instance._disposeGlobalController();
    _instance._currentPlayingVideoUrl = null;
  }
}
