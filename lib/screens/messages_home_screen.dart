import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/gradient_background.dart';
import 'dm_thread_screen.dart';
import 'choose_dm_recipient_screen.dart';
import '../utils/page_transitions.dart';
import '../models/dm_conversation.dart';

class MessagesHomeScreen extends StatefulWidget {
  final int userId;

  const MessagesHomeScreen({super.key, required this.userId});

  @override
  State<MessagesHomeScreen> createState() => _MessagesHomeScreenState();
}

class _MessagesHomeScreenState extends State<MessagesHomeScreen> {
  List<DMConversation> _conversations = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<DMConversation> _filteredConversations = [];

  @override
  void initState() {
    super.initState();
    _loadConversations();

    // Initialize filtered conversations to show all when screen loads
    _filteredConversations = _conversations;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final apiService = Provider.of<ApiService>(context, listen: false);
      final conversations = await apiService.getDMConversations();

      if (mounted) {
        setState(() {
          _conversations = conversations;
          _filteredConversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterConversations(String query) {
    final lowercaseQuery = query.toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredConversations =
            _conversations; // Show all conversations when query is empty
      });
      return;
    }

    final filtered =
        _conversations.where((conversation) {
          final otherFirstName =
              (conversation.otherUserFirstName ?? '').toLowerCase();
          final otherLastName =
              (conversation.otherUserLastName ?? '').toLowerCase();
          final otherUsername =
              (conversation.otherUserName ?? '').toLowerCase();
          final lastMessage =
              (conversation.lastMessageContent ?? '').toLowerCase();

          return otherFirstName.contains(lowercaseQuery) ||
              otherLastName.contains(lowercaseQuery) ||
              otherUsername.contains(lowercaseQuery) ||
              '$otherFirstName $otherLastName'.contains(lowercaseQuery) ||
              lastMessage.contains(lowercaseQuery);
        }).toList();

    setState(() {
      _filteredConversations = filtered;
    });
  }

  String _getInitials(String? firstName, String? lastName, String? username) {
    if (firstName != null && firstName.isNotEmpty) {
      if (lastName != null && lastName.isNotEmpty) {
        return '${firstName[0]}${lastName[0]}'.toUpperCase();
      }
      return firstName[0].toUpperCase();
    }
    if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';

    try {
      final DateTime dateTime = timestamp;
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        // Show date for messages older than a week
        return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        // Show day of week for messages within a week
        return [
          'Sun',
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
        ][dateTime.weekday - 1];
      } else if (difference.inHours > 0) {
        // Show time for messages from today
        String hour =
            (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour)
                .toString();
        if (hour == '0') hour = '12';
        String minute = dateTime.minute.toString().padLeft(2, '0');
        String period = dateTime.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $period';
      } else if (difference.inMinutes > 0) {
        // Show minutes ago for recent messages
        return '${difference.inMinutes}m';
      } else {
        return 'Now';
      }
    } catch (e) {
      return '';
    }
  }

  void _startNewConversation() {
    slidePush(context, ChooseDMRecipientScreen(userId: widget.userId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        automaticallyImplyLeading: false, // Remove back button
        title: Row(
          children: [
            // App logo
            Icon(
              Icons.message, // Replace with your app logo
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 16),
            // Messages text
            const Expanded(
              child: Text(
                'Messages',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
            ),
            // Magnifying glass icon
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {
                // Show search functionality
                showSearch(
                  context: context,
                  delegate: ConversationSearchDelegate(
                    conversations: _conversations,
                    onSelect: (conversation) {
                      final otherUserId = conversation.getOtherUserId(
                        widget.userId,
                      );
                      final conversationId = conversation.id;
                      final displayName =
                          conversation.getOtherUserDisplayName();

                      slidePush(
                        context,
                        DMThreadScreen(
                          currentUserId: widget.userId,
                          otherUserId: otherUserId,
                          otherUserName: displayName,
                          conversationId: conversationId,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            // User avatar
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.lightGreen.shade100,
              child: Text(
                'U',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8), // Add some padding at the end
          ],
        ),
      ),
      body: Column(
        children: [
          // Conversations list with gradient background
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
              ),
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error loading conversations',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadConversations,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                      : _conversations.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No conversations yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _startNewConversation,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text(
                                'Start a new conversation',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: _loadConversations,
                        child: ListView.builder(
                          itemCount: _filteredConversations.length,
                          itemBuilder: (context, index) {
                            final conversation = _filteredConversations[index];
                            return _buildConversationTile(conversation);
                          },
                        ),
                      ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewConversation,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }

  Widget _buildConversationTile(DMConversation conversation) {
    final otherUserId = conversation.getOtherUserId(widget.userId);
    final otherUsername = conversation.otherUserName;
    final otherFirstName = conversation.otherUserFirstName;
    final otherLastName = conversation.otherUserLastName;
    final lastMessageContent = conversation.lastMessageContent;
    final lastMessageTime = conversation.lastMessageTime;
    final unreadCount = conversation.unreadCount ?? 0;
    final conversationId = conversation.id;

    final displayName = conversation.getOtherUserDisplayName();
    final bool hasUnread = conversation.hasUnreadMessages ?? false;
    final String initials = conversation.getOtherUserInitials();
    final String timestamp = _formatTimestamp(lastMessageTime);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white,
          child: Text(
            initials,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
            if (timestamp.isNotEmpty)
              Text(
                timestamp,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      hasUnread ? Colors.white : Colors.white.withOpacity(0.7),
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                lastMessageContent ?? 'No messages yet',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      hasUnread
                          ? Colors.white.withOpacity(0.9)
                          : Colors.white.withOpacity(0.7),
                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                  fontStyle:
                      lastMessageContent == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasUnread && unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unreadCount',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          slidePush(
            context,
            DMThreadScreen(
              currentUserId: widget.userId,
              otherUserId: otherUserId,
              otherUserName: displayName,
              conversationId: conversationId,
            ),
          );
        },
      ),
    );
  }
}

class ConversationSearchDelegate extends SearchDelegate<DMConversation> {
  final List<DMConversation> conversations;
  final Function(DMConversation) onSelect;

  ConversationSearchDelegate({
    required this.conversations,
    required this.onSelect,
  });

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(
          context,
          DMConversation(
            id: 0,
            user1Id: 0,
            user2Id: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return buildSuggestions(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return ListView.builder(
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          return _buildConversationItem(context, conversations[index]);
        },
      );
    }

    final lowercaseQuery = query.toLowerCase();
    final results =
        conversations.where((conversation) {
          final otherFirstName =
              (conversation.otherUserFirstName ?? '').toLowerCase();
          final otherLastName =
              (conversation.otherUserLastName ?? '').toLowerCase();
          final otherUsername =
              (conversation.otherUserName ?? '').toLowerCase();
          final lastMessage =
              (conversation.lastMessageContent ?? '').toLowerCase();

          return otherFirstName.contains(lowercaseQuery) ||
              otherLastName.contains(lowercaseQuery) ||
              otherUsername.contains(lowercaseQuery) ||
              '$otherFirstName $otherLastName'.contains(lowercaseQuery) ||
              lastMessage.contains(lowercaseQuery);
        }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        return _buildConversationItem(context, results[index]);
      },
    );
  }

  Widget _buildConversationItem(
    BuildContext context,
    DMConversation conversation,
  ) {
    final displayName = conversation.getOtherUserDisplayName();
    final lastMessageContent = conversation.lastMessageContent;

    return ListTile(
      title: Text(displayName),
      subtitle: lastMessageContent != null ? Text(lastMessageContent) : null,
      onTap: () {
        close(context, conversation);
        onSelect(conversation);
      },
    );
  }
}
