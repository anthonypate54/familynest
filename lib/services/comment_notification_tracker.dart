import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for tracking last seen comment counts to show new comment indicators
class CommentNotificationTracker {
  static final CommentNotificationTracker _instance =
      CommentNotificationTracker._internal();
  factory CommentNotificationTracker() => _instance;
  CommentNotificationTracker._internal();

  static const String _keyPrefix = 'last_comment_count_';

  /// Get the last seen comment count for a message
  Future<int> getLastSeenCommentCount(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt('$_keyPrefix$messageId') ?? 0;
      debugPrint(
        '📊 COMMENT_TRACKER: Last seen count for message $messageId: $count',
      );
      return count;
    } catch (e) {
      debugPrint(
        '❌ COMMENT_TRACKER: Error getting last seen count for $messageId: $e',
      );
      return 0;
    }
  }

  /// Update the last seen comment count for a message
  Future<void> updateLastSeenCommentCount(
    String messageId,
    int commentCount,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_keyPrefix$messageId', commentCount);
      debugPrint(
        '📊 COMMENT_TRACKER: Updated last seen count for message $messageId to $commentCount',
      );
    } catch (e) {
      debugPrint(
        '❌ COMMENT_TRACKER: Error updating last seen count for $messageId: $e',
      );
    }
  }

  /// Check if a message has new comments
  Future<bool> hasNewComments(String messageId, int currentCommentCount) async {
    final lastSeenCount = await getLastSeenCommentCount(messageId);
    final hasNew = currentCommentCount > lastSeenCount;
    debugPrint(
      '📊 COMMENT_TRACKER: Message $messageId - Current: $currentCommentCount, Last seen: $lastSeenCount, Has new: $hasNew',
    );
    return hasNew;
  }

  /// Mark all comments as seen for a message (call when user opens thread)
  Future<void> markCommentsAsSeen(String messageId, int commentCount) async {
    await updateLastSeenCommentCount(messageId, commentCount);
    debugPrint(
      '✅ COMMENT_TRACKER: Marked all comments as seen for message $messageId (count: $commentCount)',
    );
  }

  /// Clear all tracked comment counts (useful for logout)
  Future<void> clearAllTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_keyPrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
      debugPrint('🗑️ COMMENT_TRACKER: Cleared all comment tracking data');
    } catch (e) {
      debugPrint('❌ COMMENT_TRACKER: Error clearing tracking data: $e');
    }
  }
}
