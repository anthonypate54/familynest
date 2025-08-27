import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

/// Simple manager - just tracks which video should be playing
class VideoControllerManager extends ChangeNotifier {
  String? _currentPlayingVideoUrl;

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
}
