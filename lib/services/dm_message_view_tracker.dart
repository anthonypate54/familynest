import 'package:flutter/foundation.dart';
import 'dart:async';
import 'api_service.dart';

/// Service for tracking DM message views and batching API calls for performance
class DMMessageViewTracker {
  static final DMMessageViewTracker _instance =
      DMMessageViewTracker._internal();
  factory DMMessageViewTracker() => _instance;
  DMMessageViewTracker._internal();

  // Store the ApiService instance from the UI components
  ApiService? _apiService;

  // Track which DM messages are pending to be marked as viewed
  final Set<String> _pendingViews = <String>{};

  // Track which DM messages have already been marked as viewed (local cache)
  final Set<String> _viewedMessages = <String>{};

  // Track timers for each DM message (to implement dwell time)
  final Map<String, Timer> _viewTimers = <String, Timer>{};

  // Batch flush timer
  Timer? _batchTimer;

  // Notifier to trigger UI updates when DM messages are marked as viewed
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
    debugPrint('🔧 DM_READ_TRACKING: ApiService instance updated');
  }

  /// Mark a DM message as potentially viewed (starts the dwell timer)
  void onMessageVisible(String dmMessageId, double visibleFraction) {
    // Only track if message is sufficiently visible and not already viewed
    if (visibleFraction >= _visibilityThreshold &&
        !_viewedMessages.contains(dmMessageId)) {
      debugPrint(
        '👁️ DM_VISIBILITY: DM Message $dmMessageId visibility changed to ${(visibleFraction * 100).toInt()}%',
      );

      // Cancel any existing timer for this message
      _viewTimers[dmMessageId]?.cancel();

      // Start a new dwell timer
      _viewTimers[dmMessageId] = Timer(_viewDwellTime, () {
        _markMessageForViewing(dmMessageId);
      });
    } else if (visibleFraction < _visibilityThreshold) {
      // Message is no longer sufficiently visible, cancel the timer
      _viewTimers[dmMessageId]?.cancel();
      _viewTimers.remove(dmMessageId);
    }
  }

  /// Mark a DM message as no longer visible (cancel dwell timer)
  void onMessageInvisible(String dmMessageId) {
    _viewTimers[dmMessageId]?.cancel();
    _viewTimers.remove(dmMessageId);
  }

  /// Internal method to mark a DM message for viewing after dwell time
  void _markMessageForViewing(String dmMessageId) {
    if (_viewedMessages.contains(dmMessageId)) {
      // Removed excessive logging for already viewed DM messages
      return;
    }

    debugPrint(
      '📝 DM_READ_TRACKING: Adding DM message $dmMessageId to pending views',
    );
    _pendingViews.add(dmMessageId);
    _viewedMessages.add(dmMessageId);

    // Trigger UI update
    _viewedMessagesNotifier.value = _viewedMessages.length;

    // Clean up timer
    _viewTimers.remove(dmMessageId);

    // Schedule batch flush if not already scheduled
    _scheduleBatchFlush();
  }

  /// Schedule a batch flush of pending views
  void _scheduleBatchFlush() {
    if (_batchTimer?.isActive == true) {
      // Timer already active
      debugPrint('🔍 DM_READ_TRACKING: Batch flush already scheduled');
      return;
    }

    debugPrint(
      '🔍 DM_READ_TRACKING: Scheduling batch flush in ${_batchFlushInterval.inSeconds}s (${_pendingViews.length} pending views)',
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
        '❌ DM_READ_TRACKING: No ApiService instance available, cannot flush views',
      );
      return;
    }

    final dmMessageIdStrings = _pendingViews.toList();
    _pendingViews.clear();

    debugPrint(
      '🚀 Flushing ${dmMessageIdStrings.length} DM message views to API: $dmMessageIdStrings',
    );

    try {
      // Convert String IDs to int IDs for the API
      final dmMessageIds =
          dmMessageIdStrings
              .map((id) => int.tryParse(id))
              .where((id) => id != null)
              .cast<int>()
              .toList();

      if (dmMessageIds.isEmpty) {
        debugPrint('❌ DM_READ_TRACKING: No valid DM message IDs to flush');
        return;
      }

      // Use the authenticated ApiService instance for DM messages
      final result = await _apiService!.markMultipleDMMessagesAsViewed(
        dmMessageIds,
      );

      if (result.containsKey('error')) {
        debugPrint('❌ DM Batch view API returned error: ${result['error']}');
        // Re-add to pending on error
        _pendingViews.addAll(dmMessageIdStrings);
      } else {
        final successCount = result['markedCount'] ?? 0;
        final requestedCount = result['requestedCount'] ?? 0;
        debugPrint(
          '✅ DM Batch view successful: $successCount marked out of $requestedCount requested',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to batch mark DM messages as viewed: $e');
      // Re-add to pending on failure
      _pendingViews.addAll(dmMessageIdStrings);
    }
  }

  /// Check if a DM message has been viewed locally
  bool isMessageViewed(String dmMessageId) {
    final isViewed = _viewedMessages.contains(dmMessageId);
    debugPrint(
      '🔍 DM_READ_TRACKING: Check if DM message $dmMessageId is viewed: $isViewed',
    );
    return isViewed;
  }

  /// Manually mark a DM message as viewed (for immediate marking)
  void markMessageAsViewed(String dmMessageId) {
    debugPrint(
      '🎯 DM_READ_TRACKING: Manually marking DM message $dmMessageId as viewed',
    );
    _markMessageForViewing(dmMessageId);
  }

  /// Force flush all pending views immediately
  void flushNow() {
    debugPrint('🚀 DM_READ_TRACKING: Force flushing pending views');
    _batchTimer?.cancel();
    _flushPendingViews();
  }

  /// Clear all tracking state (for testing/debugging)
  void clear() {
    debugPrint('🧹 DM_READ_TRACKING: Clearing all tracking state');
    _pendingViews.clear();
    _viewedMessages.clear();
    for (final timer in _viewTimers.values) {
      timer.cancel();
    }
    _viewTimers.clear();
    _batchTimer?.cancel();
    _viewedMessagesNotifier.value = 0;
  }

  /// Get debug statistics
  Map<String, dynamic> getStats() {
    return {
      'pendingViews': _pendingViews.length,
      'viewedMessages': _viewedMessages.length,
      'activeTimers': _viewTimers.length,
      'batchTimerActive': _batchTimer?.isActive ?? false,
    };
  }

  /// Clear all views (for testing)
  void clearAllViews() {
    debugPrint('🧹 DM_READ_TRACKING: Clearing all views');
    _viewedMessages.clear();
    _viewedMessagesNotifier.value = 0;
  }

  /// Clear a specific DM message from cache (useful when message is updated)
  void clearMessageFromCache(String dmMessageId) {
    _viewedMessages.remove(dmMessageId);
    _pendingViews.remove(dmMessageId);
    _viewTimers[dmMessageId]?.cancel();
    _viewTimers.remove(dmMessageId);
  }

  /// Get the list of viewed DM messages
  Set<String> getViewedMessages() {
    return Set.from(_viewedMessages);
  }
}
