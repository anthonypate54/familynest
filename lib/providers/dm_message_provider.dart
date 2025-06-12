import 'package:flutter/material.dart';
import '../models/dm_message.dart';

class DMMessageProvider extends ChangeNotifier {
  Map<int, List<DMMessage>> _conversationMessages = {};

  List<DMMessage> getMessages(int conversationId) {
    return _conversationMessages[conversationId] ?? [];
  }

  void setMessages(int conversationId, List<DMMessage> messages) {
    _conversationMessages[conversationId] = messages;
    notifyListeners();
  }

  void addMessage(int conversationId, DMMessage message) {
    if (_conversationMessages[conversationId] == null) {
      _conversationMessages[conversationId] = [];
    }
    _conversationMessages[conversationId]!.insert(0, message);
    notifyListeners();
  }

  void clearMessages(int conversationId) {
    _conversationMessages[conversationId] = [];
    notifyListeners();
  }
}
