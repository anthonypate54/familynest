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

    // Check for duplicates before adding (prevent optimistic update conflicts)
    final existingMessages = _conversationMessages[conversationId]!;
    final isDuplicate = existingMessages.any(
      (existingMessage) => existingMessage.id == message.id,
    );

    if (!isDuplicate) {
      debugPrint(
        '📝 DMMessageProvider: Adding message ${message.id} to conversation $conversationId',
      );
      debugPrint(
        '📝 DMMessageProvider: Current message count: ${existingMessages.length}',
      );
      _conversationMessages[conversationId]!.insert(0, message);
      debugPrint(
        '📝 DMMessageProvider: New message count: ${_conversationMessages[conversationId]!.length}',
      );
      debugPrint('📝 DMMessageProvider: Calling notifyListeners()');
      notifyListeners();
    } else {
      debugPrint(
        '⚠️ DMMessageProvider: Duplicate message ${message.id}, not adding',
      );
    }
  }

  void clearMessages(int conversationId) {
    _conversationMessages[conversationId] = [];
    notifyListeners();
  }

  // Mark messages from other users in a conversation as read
  // Only marks messages from OTHER users, not your own messages
  void markOtherUsersMessagesAsRead(int conversationId, int currentUserId) {
    final messages = _conversationMessages[conversationId];
    if (messages != null) {
      bool hasChanges = false;

      _conversationMessages[conversationId] =
          messages.map((message) {
            // Only mark messages from OTHER users as read, not your own messages
            if (message.senderId != currentUserId && !message.isRead) {
              hasChanges = true;
              return DMMessage(
                id: message.id,
                conversationId: message.conversationId,
                senderId: message.senderId,
                content: message.content,
                mediaUrl: message.mediaUrl,
                mediaType: message.mediaType,
                mediaThumbnail: message.mediaThumbnail,
                mediaFilename: message.mediaFilename,
                mediaSize: message.mediaSize,
                mediaDuration: message.mediaDuration,
                localMediaPath: message.localMediaPath,
                isRead: true, // Mark as read
                deliveredAt: message.deliveredAt,
                createdAt: message.createdAt,
                updatedAt: message.updatedAt,
                senderUsername: message.senderUsername,
                senderPhoto: message.senderPhoto,
                senderFirstName: message.senderFirstName,
                senderLastName: message.senderLastName,
              );
            } else {
              // Keep your own messages and already-read messages unchanged
              return message;
            }
          }).toList();

      if (hasChanges) {
        debugPrint(
          '✅ DMMessageProvider: Marked other users\' unread messages in conversation $conversationId as read',
        );
        notifyListeners();
      }
    }
  }

  void updateMessage(int conversationId, DMMessage updatedMessage) {
    final messages = _conversationMessages[conversationId];
    if (messages != null) {
      final messageIndex = messages.indexWhere(
        (message) => message.id == updatedMessage.id,
      );
      if (messageIndex != -1) {
        debugPrint(
          '🔄 DMMessageProvider: Updating message ${updatedMessage.id} in conversation $conversationId',
        );
        _conversationMessages[conversationId]![messageIndex] = updatedMessage;
        notifyListeners();
      } else {
        debugPrint(
          '⚠️ DMMessageProvider: Message ${updatedMessage.id} not found in conversation $conversationId',
        );
      }
    }
  }
}
