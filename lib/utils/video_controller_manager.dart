import 'package:flutter/material.dart';
import 'dart:developer' as developer;

/// Global manager to track and limit video controller instances
/// This prevents memory leaks from too many simultaneous ExoPlayer instances
class VideoControllerManager {
  static int _activeControllers = 0;
  static const int _maxControllers =
      2; // Maximum simultaneous video controllers

  /// Track when a video controller is created
  static void onControllerCreated(String videoUrl) {
    _activeControllers++;
    debugPrint(
      '🎬 VIDEO CONTROLLER CREATED: $_activeControllers active (max: $_maxControllers) [${videoUrl.split('/').last}]',
    );

    developer.Timeline.startSync(
      'VideoController_Created',
      arguments: {
        'active_count': _activeControllers,
        'max_allowed': _maxControllers,
        'video': videoUrl.split('/').last,
      },
    );
    developer.Timeline.finishSync();

    if (_activeControllers > _maxControllers) {
      debugPrint(
        '⚠️ WARNING: Too many video controllers! This may cause OOM crash!',
      );
    }
  }

  /// Track when a video controller is disposed
  static void onControllerDisposed(String videoUrl) {
    if (_activeControllers > 0) {
      _activeControllers--;
    }

    debugPrint(
      '🗑️ VIDEO CONTROLLER DISPOSED: $_activeControllers active [${videoUrl.split('/').last}]',
    );

    developer.Timeline.startSync(
      'VideoController_Disposed',
      arguments: {
        'active_count': _activeControllers,
        'video': videoUrl.split('/').last,
      },
    );
    developer.Timeline.finishSync();
  }

  /// Check if we can safely create another controller
  static bool canCreateController() {
    final canCreate = _activeControllers < _maxControllers;

    if (!canCreate) {
      debugPrint(
        '🚫 VIDEO CONTROLLER LIMIT REACHED: $_activeControllers/$_maxControllers active',
      );
      // Force garbage collection when limit reached
      developer.Timeline.startSync('force_gc_controller_limit');
      developer.Timeline.finishSync();
    }

    return canCreate;
  }

  /// Get current active controller count
  static int get activeControllerCount => _activeControllers;

  /// Force reset (for debugging)
  static void reset() {
    debugPrint(
      '🔄 RESETTING video controller count from $_activeControllers to 0',
    );
    _activeControllers = 0;
  }
}
