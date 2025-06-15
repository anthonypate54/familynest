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
    _messages.insert(0, message);
    notifyListeners();
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
