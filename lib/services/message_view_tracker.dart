import 'package:flutter/foundation.dart';
import 'dart:async';
import 'api_service.dart';

/// Service for tracking message views and batching API calls for performance
class MessageViewTracker {
  static final MessageViewTracker _instance = MessageViewTracker._internal();
  factory MessageViewTracker() => _instance;
  MessageViewTracker._internal();

  // Store the ApiService instance from the UI components
  ApiService? _apiService;

  // Track which messages are pending to be marked as viewed
  final Set<String> _pendingViews = <String>{};

  // Track which messages have already been marked as viewed (local cache)
  final Set<String> _viewedMessages = <String>{};

  // Track timers for each message (to implement dwell time)
  final Map<String, Timer> _viewTimers = <String, Timer>{};

  // Batch flush timer
  Timer? _batchTimer;

  // Notifier to trigger UI updates when messages are marked as viewed
  final ValueNotifier<int> _viewedMessagesNotifier = ValueNotifier<int>(0);

  // Configuration
  static const Duration _viewDwellTime = Duration(
    seconds: 2,
  ); // How long to be visible
  static const Duration _batchFlushInterval = Duration(
    seconds: 3,
  ); // How often to flush to API
  static const double _visibilityThreshold =
      0.3; // 30% visible to count as viewed (lowered for text messages)

  /// Get the notifier for UI updates
  ValueNotifier<int> get viewedMessagesNotifier => _viewedMessagesNotifier;

  /// Set the ApiService instance to use for API calls
  void setApiService(ApiService apiService) {
    _apiService = apiService;
    // Remove excessive logging - only log once when first set
    if (!_isApiServiceSet) {
      debugPrint('🔧 READ_TRACKING: ApiService instance updated');
      _isApiServiceSet = true;
    }
  }

  // Track if ApiService has been set to avoid spam
  bool _isApiServiceSet = false;

  /// Mark a message as potentially viewed (starts the dwell timer)
  void onMessageVisible(String messageId, double visibleFraction) {
    // Skip if already viewed or pending
    if (_viewedMessages.contains(messageId) ||
        _pendingViews.contains(messageId)) {
      // Removed excessive logging for already viewed messages
      return;
    }

    // Only track if message is sufficiently visible and not already viewed
    if (visibleFraction >= _visibilityThreshold) {
      debugPrint(
        '🔍 READ_TRACKING: Message $messageId became visible (${(visibleFraction * 100).toInt()}%)',
      );
      debugPrint(
        '🔍 READ_TRACKING: Starting ${_viewDwellTime.inSeconds}s dwell timer for message $messageId',
      );

      // Start dwell timer
      _viewTimers[messageId] = Timer(_viewDwellTime, () {
        debugPrint(
          '🔍 READ_TRACKING: Dwell timer completed for message $messageId - marking as viewed',
        );
        _markAsViewed(messageId);
      });
    } else {
      if (_viewedMessages.contains(messageId)) {
        debugPrint(
          '🔍 READ_TRACKING: Message $messageId already viewed, skipping',
        );
      } else if (_pendingViews.contains(messageId)) {
        debugPrint(
          '🔍 READ_TRACKING: Message $messageId already pending, skipping',
        );
      } else if (visibleFraction < _visibilityThreshold) {
        debugPrint(
          '🔍 READ_TRACKING: Message $messageId not visible enough (${(visibleFraction * 100).toInt()}% < ${(_visibilityThreshold * 100).toInt()}%) - needs ${(_visibilityThreshold * 100).toInt()}%+',
        );
      }
    }
  }

  /// Cancel view tracking when message becomes invisible
  void onMessageInvisible(String messageId) {
    final timer = _viewTimers.remove(messageId);
    if (timer != null) {
      timer.cancel();
      debugPrint(
        '🔍 READ_TRACKING: Message $messageId became invisible - cancelled dwell timer',
      );
    }
  }

  /// Immediately mark a message as viewed (e.g., when user taps it)
  void markAsViewedImmediately(String messageId) {
    if (!_viewedMessages.contains(messageId)) {
      // Cancel any pending timer
      _viewTimers.remove(messageId)?.cancel();

      debugPrint(
        '🔍 READ_TRACKING: Immediately marking message $messageId as viewed (user interaction)',
      );
      // Mark as viewed immediately
      _markAsViewed(messageId);
    }
  }

  /// Internal method to add message to viewed queue
  void _markAsViewed(String messageId) {
    if (_viewedMessages.contains(messageId)) {
      return; // Already viewed
    }

    debugPrint('🔍 READ_TRACKING: ✅ Marking message $messageId as viewed');
    debugPrint(
      '🔍 READ_TRACKING: Adding to pending batch (current batch size: ${_pendingViews.length})',
    );

    // Add to local cache and pending queue
    _viewedMessages.add(messageId);
    _pendingViews.add(messageId);

    // Notify UI that a message was marked as viewed
    _viewedMessagesNotifier.value = _viewedMessages.length;

    _scheduleBatchFlush();
  }

  void _scheduleBatchFlush() {
    _batchTimer?.cancel();
    debugPrint(
      '🔍 READ_TRACKING: Scheduling batch flush in ${_batchFlushInterval.inSeconds}s (${_pendingViews.length} pending views)',
    );
    _batchTimer = Timer(_batchFlushInterval, () {
      _flushPendingViews();
    });
  }

  void _flushPendingViews() async {
    if (_pendingViews.isEmpty) {
      return;
    }

    if (_apiService == null) {
      debugPrint(
        '❌ READ_TRACKING: No ApiService instance available, cannot flush views',
      );
      return;
    }

    final messageIdStrings = _pendingViews.toList();
    _pendingViews.clear();

    debugPrint(
      '🚀 Flushing ${messageIdStrings.length} message views to API: $messageIdStrings',
    );

    try {
      // Convert String IDs to int IDs for the API
      final messageIds =
          messageIdStrings
              .map((id) => int.tryParse(id))
              .where((id) => id != null)
              .cast<int>()
              .toList();

      if (messageIds.isEmpty) {
        debugPrint('❌ READ_TRACKING: No valid message IDs to flush');
        return;
      }

      // Use the authenticated ApiService instance
      final result = await _apiService!.markMultipleMessagesAsViewed(
        messageIds,
      );

      if (result.containsKey('error')) {
        debugPrint('❌ Batch view API returned error: ${result['error']}');
        // Re-add to pending on error
        _pendingViews.addAll(messageIdStrings);
      } else {
        final successCount = result['successCount'] ?? 0;
        final skippedCount = result['skippedCount'] ?? 0;
        debugPrint(
          '✅ Batch view successful: $successCount marked, $skippedCount skipped',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to batch mark messages as viewed: $e');
      // Re-add to pending on failure
      _pendingViews.addAll(messageIdStrings);
    }
  }

  /// Check if a message has been viewed locally
  bool isMessageViewed(String messageId) {
    final isViewed = _viewedMessages.contains(messageId);
    debugPrint(
      '🔍 READ_TRACKING: Checking if message $messageId is viewed: $isViewed',
    );
    return isViewed;
  }

  /// Force clear a message from viewed cache (for debugging)
  void clearMessageFromCache(String messageId) {
    final wasPresent = _viewedMessages.remove(messageId);
    if (wasPresent) {
      _viewedMessagesNotifier.value = _viewedMessages.length;
      debugPrint(
        '🔍 READ_TRACKING: Cleared message $messageId from viewed cache',
      );
    }
  }

  /// Get all viewed message IDs (for debugging)
  Set<String> getViewedMessages() {
    return Set.from(_viewedMessages);
  }

  /// Clear all tracked views (e.g., on logout)
  void clearAllViews() {
    _pendingViews.clear();
    _viewedMessages.clear();
    _viewTimers.forEach((key, timer) => timer.cancel());
    _viewTimers.clear();
    _batchTimer?.cancel();
    _batchTimer = null;
    _viewedMessagesNotifier.value = 0;
    debugPrint('🔍 READ_TRACKING: Cleared all message views');
  }

  /// Manually flush pending views (useful for app lifecycle events)
  Future<void> flushNow() async {
    _batchTimer?.cancel();
    _flushPendingViews();
  }

  /// Get stats for debugging
  Map<String, dynamic> getStats() {
    return {
      'viewedMessages': _viewedMessages.length,
      'pendingViews': _pendingViews.length,
      'activeTimers': _viewTimers.length,
    };
  }

  /// Clear all tracking data (alias for clearAllViews for backwards compatibility)
  void clear() {
    clearAllViews();
  }
}
