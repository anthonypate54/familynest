import 'package:flutter/material.dart';
import '../models/message.dart';

class MessageProvider extends ChangeNotifier {
  List<Message> _messages = [];

  List<Message> get messages => _messages;

  void setMessages(List<Message> newMessages) {
    _messages = newMessages;
    notifyListeners();
  }

  void addMessage(Message message) {
    debugPrint(
      '📝 MessageProvider.addMessage: Attempting to add message ${message.id}',
    );
    debugPrint(
      '📝 MessageProvider.addMessage: Current message count: ${_messages.length}',
    );

    // Check if message already exists to prevent duplicates
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    if (existingIndex == -1) {
      // Message doesn't exist, add it
      _messages.insert(0, message);
      debugPrint(
        'Added new message ${message.id} at position 0',
      );
      debugPrint(
        '📝 MessageProvider.addMessage: New message count: ${_messages.length}',
      );
      notifyListeners();
    } else {
      // Message already exists, update it instead
      _messages[existingIndex] = message;
      debugPrint(
        'Updated existing message ${message.id} at position $existingIndex',
      );
      notifyListeners();
    }
  }

  void mergeMessages(List<Message> newMessages) {
    debugPrint(
      '📝 MessageProvider.mergeMessages: Merging ${newMessages.length} new messages',
    );
    debugPrint(
      '📝 MessageProvider.mergeMessages: Current message count: ${_messages.length}',
    );

    // Create a set of existing message IDs for efficient lookup
    final existingIds = _messages.map((m) => m.id).toSet();

    // Add only messages that don't already exist
    final uniqueNewMessages =
        newMessages.where((msg) => !existingIds.contains(msg.id)).toList();

    if (uniqueNewMessages.isNotEmpty) {
      // Add new messages to the current list
      _messages.addAll(uniqueNewMessages);

      // Sort by timestamp (newest first)
      _messages.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );

      debugPrint(
        'Added ${uniqueNewMessages.length} new messages, total: ${_messages.length}',
      );
      notifyListeners();
    } else {
      debugPrint('📝 MessageProvider.mergeMessages: No new messages to add');
    }
  }

  void updateMessage(Message updated) {
    final idx = _messages.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      _messages[idx] = updated;
      notifyListeners();
    }
  }

  void updateMessageLoveCount(String messageId, int loveCount) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(loveCount: loveCount);
      notifyListeners();
    }
  }

  void incrementCommentCount(String messageId) {
    final idx = _messages.indexWhere((m) {
      return m.id == messageId;
    });
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(commentCount: (msg.commentCount ?? 0) + 1);
      notifyListeners();
    }
  }

  // Clear all messages (for logout)
  void clear() {
    _messages = [];
    notifyListeners();
  }

  void updateMessageCommentCount(
    String messageId,
    int commentCount, {
    bool? hasUnreadComments,
  }) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      // Debug: Uncomment for notification debugging
      // debugPrint('Updating message $messageId commentCount: ${msg.commentCount} → $commentCount, hasUnreadComments: ${msg.hasUnreadComments} → $hasUnreadComments');
      _messages[idx] = msg.copyWith(
        commentCount: commentCount,
        hasUnreadComments: hasUnreadComments,
      );
      notifyListeners();
      // Debug: Uncomment for notification debugging
      // debugPrint('Message $messageId updated and listeners notified');
    } else {
      // Debug: Uncomment for notification debugging
      // debugPrint('Message $messageId not found in provider');
    }
  }

  void incrementLikeCount(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(likeCount: (msg.likeCount ?? 0) + 1);
      notifyListeners();
    }
  }

  void decrementLikeCount(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(likeCount: (msg.likeCount ?? 0) - 1);
      notifyListeners();
    }
  }

  void incrementLoveCount(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(loveCount: (msg.loveCount ?? 0) + 1);
      notifyListeners();
    }
  }

  void decrementLoveCount(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(loveCount: (msg.loveCount ?? 0) - 1);
      notifyListeners();
    }
  }

  void updateMessageLikeCount(String messageId, int newCount) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(likeCount: newCount);
      notifyListeners();
    }
  }

  void updateMessageReactions(
    String messageId, {
    int? likeCount,
    int? loveCount,
    bool? isLiked,
    bool? isLoved,
  }) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(
        likeCount: likeCount ?? msg.likeCount,
        loveCount: loveCount ?? msg.loveCount,
        isLiked: isLiked ?? msg.isLiked,
        isLoved: isLoved ?? msg.isLoved,
      );
      notifyListeners();
    }
  }
}
