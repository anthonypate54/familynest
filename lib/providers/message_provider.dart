import 'package:flutter/material.dart';
import '../models/message.dart';

class MessageProvider extends ChangeNotifier {
  List<Message> _messages = [];

  List<Message> get messages => _messages;

  void setMessages(List<Message> newMessages) {
    _messages = newMessages;
    notifyListeners();
  }

  void updateMessage(Message updated) {
    final idx = _messages.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      _messages[idx] = updated;
      notifyListeners();
    }
  }

  void incrementCommentCount(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      _messages[idx] = msg.copyWith(commentCount: (msg.commentCount ?? 0) + 1);
      notifyListeners();
    }
  }
}
