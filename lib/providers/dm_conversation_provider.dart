import 'package:flutter/material.dart';
import '../models/dm_conversation.dart';

class DMConversationProvider extends ChangeNotifier {
  List<DMConversation> _conversations = [];
  bool _isLoading = false;
  String _searchQuery = '';
  List<DMConversation> _filteredConversations = [];

  // Getters
  List<DMConversation> get conversations => _conversations;
  List<DMConversation> get filteredConversations =>
      _searchQuery.isEmpty ? _conversations : _filteredConversations;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  // Set conversations from API
  void setConversations(List<DMConversation> conversations) {
    _conversations = conversations;
    _applyFilter();
    notifyListeners();
  }

  // Add a new conversation
  void addConversation(DMConversation conversation) {
    // Check if conversation already exists
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      // Update existing conversation
      _conversations[index] = conversation;
    } else {
      // Add new conversation
      _conversations.add(conversation);
    }
    _applyFilter();
    notifyListeners();
  }

  // Update an existing conversation
  void updateConversation(DMConversation conversation) {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      _conversations[index] = conversation;
      _applyFilter();
      notifyListeners();
    }
  }

  // Remove a conversation
  void removeConversation(int conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _applyFilter();
    notifyListeners();
  }

  // Set loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Set search query and filter conversations
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  // Apply search filter to conversations
  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredConversations = _conversations;
      return;
    }

    final query = _searchQuery.toLowerCase();
    _filteredConversations =
        _conversations.where((conversation) {
          // Search by user name
          final userName = conversation.getOtherUserDisplayName().toLowerCase();
          if (userName.contains(query)) return true;

          // Search by last message content
          final lastMessage =
              conversation.lastMessageContent?.toLowerCase() ?? '';
          if (lastMessage.contains(query)) return true;

          return false;
        }).toList();
  }

  // Get a conversation by ID
  DMConversation? getConversationById(int conversationId) {
    try {
      return _conversations.firstWhere((c) => c.id == conversationId);
    } catch (e) {
      return null;
    }
  }

  // Get a conversation by other user ID
  DMConversation? getConversationByOtherUserId(
    int otherUserId,
    int currentUserId,
  ) {
    try {
      return _conversations.firstWhere(
        (c) =>
            c.user1Id != null &&
            c.user2Id != null &&
            ((c.user1Id == currentUserId && c.user2Id == otherUserId) ||
                (c.user1Id == otherUserId && c.user2Id == currentUserId)),
      );
    } catch (e) {
      return null;
    }
  }

  // Update last message for a conversation
  void updateLastMessage({
    required int conversationId,
    required String content,
    required int senderId,
    required DateTime messageTime,
  }) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      final conversation = _conversations[index];
      _conversations[index] = conversation.copyWith(
        lastMessageContent: content,
        lastMessageSenderId: senderId,
        lastMessageTime: messageTime,
        updatedAt: DateTime.now(),
      );
      _applyFilter();
      notifyListeners();
    }
  }

  // Mark a conversation as read
  void markConversationAsRead(int conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      final conversation = _conversations[index];
      _conversations[index] = conversation.copyWith(
        hasUnreadMessages: false,
        unreadCount: 0,
      );
      _applyFilter();
      notifyListeners();
    }
  }

  // Clear all conversations
  void clearConversations() {
    _conversations = [];
    _filteredConversations = [];
    notifyListeners();
  }
}
