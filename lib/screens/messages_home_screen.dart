import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/gradient_background.dart';
import 'dm_thread_screen.dart';
import 'choose_dm_recipient_screen.dart';
import '../utils/page_transitions.dart';
import '../models/dm_conversation.dart';
import '../models/dm_message.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'message_search_screen.dart';
import '../theme/app_theme.dart';

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

  // WebSocket state variables
  WebSocketMessageHandler? _dmMessageHandler;
  bool _isWebSocketConnected = false;
  ConnectionStatusHandler? _connectionListener;
  WebSocketService? _webSocketService;

  @override
  void initState() {
    super.initState();
    // Store WebSocket service reference early
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);

    _loadConversations();

    // Initialize filtered conversations to show all when screen loads
    _filteredConversations = _conversations;

    // Delay WebSocket initialization until after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWebSocket();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();

    // Clean up WebSocket subscriptions
    if (_webSocketService != null && _dmMessageHandler != null) {
      _webSocketService!.unsubscribe(
        '/topic/dm/${widget.userId}',
        _dmMessageHandler!,
      );
    }
    if (_webSocketService != null && _connectionListener != null) {
      _webSocketService!.removeConnectionListener(_connectionListener!);
    }

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

      // Debug logging to see what we're getting
      debugPrint(
        '📱 MessagesHomeScreen: Loaded ${conversations.length} conversations',
      );
      for (int i = 0; i < conversations.length; i++) {
        final conv = conversations[i];
        debugPrint(
          '📱 Conversation $i: ${conv.otherUserName} - "${conv.lastMessageContent}" - ${conv.lastMessageTime}',
        );
      }

      if (mounted) {
        setState(() {
          _conversations = conversations;
          _filteredConversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ MessagesHomeScreen: Error loading conversations: $e');
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

      // Handle future dates (shouldn't happen but just in case)
      if (difference.isNegative) {
        return 'Now';
      }

      if (difference.inDays > 7) {
        // Show date for messages older than a week
        return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        // Show day of week for messages within a week
        final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        return days[dateTime.weekday - 1];
      } else if (difference.inHours > 0) {
        // Show hours for messages within a day
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        // Show minutes for messages within an hour
        return '${difference.inMinutes}m';
      } else {
        // Show "Now" for messages within a minute
        return 'Now';
      }
    } catch (e) {
      debugPrint('Error formatting timestamp: $e');
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
        backgroundColor: AppTheme.getAppBarColor(context),
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
                // Navigate to comprehensive search screen
                slidePush(context, MessageSearchScreen(userId: widget.userId));
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
                  colors:
                      Theme.of(context).brightness == Brightness.dark
                          ? [
                            // Dark mode: subtle gradient using dark colors
                            AppTheme.darkBackgroundColor,
                            AppTheme.darkSurfaceColor,
                          ]
                          : [
                            // Light mode: original bright gradient
                            AppTheme.primaryColor,
                            AppTheme.secondaryColor,
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
    final otherUserPhoto = conversation.otherUserPhoto; // Get the photo URL

    // Debug logging for avatar
    debugPrint(
      '🖼️ Avatar debug for ${conversation.otherUserName}: photo="$otherUserPhoto"',
    );

    final displayName = conversation.getOtherUserDisplayName();
    final bool hasUnread = conversation.hasUnreadMessages ?? false;
    final String initials = conversation.getOtherUserInitials();
    final String timestamp = _formatTimestamp(lastMessageTime);

    // Determine what to show as the last message
    String messagePreview;
    if (lastMessageContent != null && lastMessageContent.isNotEmpty) {
      messagePreview = lastMessageContent;
    } else {
      messagePreview = 'No messages yet';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAvatar(otherUserPhoto, initials, hasUnread),
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
                messagePreview,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      hasUnread
                          ? Colors.white.withOpacity(0.9)
                          : Colors.white.withOpacity(0.7),
                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                  fontStyle:
                      lastMessageContent == null || lastMessageContent.isEmpty
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
              otherUserPhoto: otherUserPhoto,
              conversationId: conversationId,
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, String initials, bool hasUnread) {
    final apiService = Provider.of<ApiService>(context, listen: false);

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: hasUnread ? Colors.white : Colors.white.withOpacity(0.3),
          width: hasUnread ? 2.0 : 1.0,
        ),
      ),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: Color(initials.hashCode | 0xFF000000),
        child:
            photoUrl != null && photoUrl.isNotEmpty
                ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl:
                        photoUrl.startsWith('http')
                            ? photoUrl
                            : apiService.mediaBaseUrl + photoUrl,
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    placeholder:
                        (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) {
                      return Text(
                        initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      );
                    },
                  ),
                )
                : Text(
                  initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
      ),
    );
  }

  // Initialize WebSocket for DM message updates
  void _initWebSocket() {
    if (_webSocketService == null) return;

    // Create message handler for DM messages
    _dmMessageHandler = (Map<String, dynamic> data) {
      _handleIncomingDMMessage(data);
    };

    // Create connection status listener
    _connectionListener = (isConnected) {
      if (mounted) {
        // Use post-frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isWebSocketConnected = isConnected;
            });
          }
        });
      }
    };

    // Subscribe to DM messages for this user
    _webSocketService!.subscribe(
      '/topic/dm/${widget.userId}',
      _dmMessageHandler!,
    );

    // Listen for connection status changes
    _webSocketService!.addConnectionListener(_connectionListener!);

    // Initialize WebSocket connection if not already connected
    _webSocketService!.initialize();
  }

  // Handle incoming DM messages from WebSocket
  void _handleIncomingDMMessage(Map<String, dynamic> data) {
    try {
      debugPrint('📨 MESSAGES_HOME: Received WebSocket message: $data');

      // Check if this is a DM message type
      final messageType = data['type'] as String?;
      if (messageType != null && messageType != 'DM_MESSAGE') {
        debugPrint('⚠️ MESSAGES_HOME: Not a DM message, ignoring');
        return;
      }

      final message = DMMessage.fromJson(data);
      debugPrint('📨 MESSAGES_HOME: Parsed message: ${message.content}');

      // Update the conversation list with the new message
      _updateConversationWithNewMessage(message);
    } catch (e, stackTrace) {
      debugPrint('❌ MESSAGES_HOME: Error handling WebSocket message: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Update conversation list when new message arrives
  void _updateConversationWithNewMessage(DMMessage message) {
    if (!mounted) return;

    setState(() {
      // Find the conversation this message belongs to
      final conversationIndex = _conversations.indexWhere(
        (conv) => conv.id == message.conversationId,
      );

      if (conversationIndex != -1) {
        // Update existing conversation
        final conversation = _conversations[conversationIndex];

        // Create updated conversation with new message info
        final updatedConversation = DMConversation(
          id: conversation.id,
          user1Id: conversation.user1Id,
          user2Id: conversation.user2Id,
          familyContextId: conversation.familyContextId,
          createdAt: conversation.createdAt,
          updatedAt: DateTime.now(), // Update timestamp
          otherUserName: conversation.otherUserName,
          otherUserPhoto: conversation.otherUserPhoto,
          otherUserFirstName: conversation.otherUserFirstName,
          otherUserLastName: conversation.otherUserLastName,
          lastMessageContent: message.content, // Update last message
          lastMessageTime: message.createdAt, // Update last message time
          lastMessageSenderId: message.senderId, // Set sender ID
          hasUnreadMessages: true, // Mark as having unread messages
          unreadCount:
              (conversation.unreadCount ?? 0) + 1, // Increment unread count
        );

        // Remove old conversation and add updated one at the top
        _conversations.removeAt(conversationIndex);
        _conversations.insert(0, updatedConversation);

        // Update filtered conversations if search is active
        if (_searchController.text.isNotEmpty) {
          _filterConversations(_searchController.text);
        } else {
          _filteredConversations = List.from(_conversations);
        }

        debugPrint(
          '✅ MESSAGES_HOME: Updated conversation ${message.conversationId} with new message',
        );
      } else {
        debugPrint(
          '⚠️ MESSAGES_HOME: Conversation ${message.conversationId} not found, refreshing list',
        );
        // If conversation not found, refresh the entire list
        _loadConversations();
      }
    });
  }
}
