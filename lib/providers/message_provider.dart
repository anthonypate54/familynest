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
        '✅ MessageProvider.addMessage: Added new message ${message.id} at position 0',
      );
      debugPrint(
        '📝 MessageProvider.addMessage: New message count: ${_messages.length}',
      );
      notifyListeners();
    } else {
      // Message already exists, update it instead
      _messages[existingIndex] = message;
      debugPrint(
        '🔄 MessageProvider.addMessage: Updated existing message ${message.id} at position $existingIndex',
      );
      notifyListeners();
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
}
