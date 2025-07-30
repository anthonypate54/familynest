import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';
import '../providers/dm_message_provider.dart';
import '../services/websocket_service.dart';
import '../models/dm_conversation.dart';
import '../models/dm_message.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../utils/page_transitions.dart';
import 'message_search_screen.dart';
import 'choose_dm_recipient_screen.dart';
import 'dm_thread_screen.dart';
import 'group_management_screen.dart';
import '../utils/group_avatar_utils.dart'; // Import the shared utility
import '../screens/profile_screen.dart';

class MessagesHomeScreen extends StatefulWidget {
  final int userId;

  const MessagesHomeScreen({super.key, required this.userId});

  // Static callbacks for communication with DMThreadScreen
  static void Function(int)? updateReadStatus;
  static void Function(DMMessage)? updateConversationWithMessage;

  @override
  State<MessagesHomeScreen> createState() => _MessagesHomeScreenState();
}

class _MessagesHomeScreenState extends State<MessagesHomeScreen>
    with WidgetsBindingObserver {
  List<DMConversation> _conversations = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasNavigatedAway = false;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<DMConversation> _filteredConversations = [];

  // WebSocket related
  WebSocketService? _webSocketService;
  Function(Map<String, dynamic>)? _dmMessageHandler;
  Function(bool)? _connectionListener;
  bool _isWebSocketConnected = false;

  @override
  void initState() {
    super.initState();
    // Store WebSocket service reference early
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);

    // Set up the static callback for read status updates
    MessagesHomeScreen.updateReadStatus = _markConversationAsRead;

    // Set up the static callback for conversation message updates
    MessagesHomeScreen.updateConversationWithMessage =
        _updateConversationWithNewMessage;

    // Add observer to detect app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

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

    // Remove the observer
    WidgetsBinding.instance.removeObserver(this);

    // Clean up WebSocket subscriptions
    if (_webSocketService != null && _dmMessageHandler != null) {
      _webSocketService!.unsubscribe(
        '/topic/dm-list/${widget.userId}',
        _dmMessageHandler!,
      );
    }
    if (_webSocketService != null && _connectionListener != null) {
      _webSocketService!.removeConnectionListener(_connectionListener!);
    }

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If we've navigated away and come back, refresh the conversations
    if (_hasNavigatedAway && !_isLoading) {
      debugPrint(
        '🔄 Returned to MessagesHomeScreen, refreshing conversations...',
      );
      _hasNavigatedAway = false;
      _loadConversations();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        '🔄 App resumed, refreshing conversations on MessagesHomeScreen...',
      );
      _loadConversations();
    }
  }

  @override
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

  void _filterConversations(String query) async {
    debugPrint('🔍 FILTER: _filterConversations called with query: "$query"');
    final lowercaseQuery = query.toLowerCase();

    if (query.isEmpty) {
      debugPrint('🔍 FILTER: Query is empty, showing all conversations');
      setState(() {
        _filteredConversations =
            _conversations; // Show all conversations when query is empty
      });
      return;
    }

    debugPrint('🔍 FILTER: About to call backend search...');
    try {
      // Use backend search for comprehensive results
      final apiService = Provider.of<ApiService>(context, listen: false);
      debugPrint('🔍 FILTER: Got apiService, calling searchDMConversations...');
      final searchResults = await apiService.searchDMConversations(query);

      setState(() {
        _filteredConversations = searchResults;
      });

      debugPrint(
        '🔍 Search completed: found ${searchResults.length} results for "$query"',
      );
    } catch (e) {
      debugPrint('❌ Search error: $e');
      // Fallback to local search if backend search fails
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

            // For group chats, also search group name and participant names
            final groupName = (conversation.name ?? '').toLowerCase();

            // Search participant names if this is a group chat
            String participantNames = '';
            if (conversation.isGroup && conversation.participants != null) {
              participantNames =
                  conversation.participants!
                      .map((p) {
                        final firstName =
                            (p['first_name'] as String? ??
                                    p['firstName'] as String? ??
                                    '')
                                .toLowerCase();
                        final lastName =
                            (p['last_name'] as String? ??
                                    p['lastName'] as String? ??
                                    '')
                                .toLowerCase();
                        final username =
                            (p['username'] as String? ?? '').toLowerCase();
                        return '$firstName $lastName $username';
                      })
                      .join(' ')
                      .toLowerCase();
            }

            return otherFirstName.contains(lowercaseQuery) ||
                otherLastName.contains(lowercaseQuery) ||
                otherUsername.contains(lowercaseQuery) ||
                '$otherFirstName $otherLastName'.contains(lowercaseQuery) ||
                lastMessage.contains(lowercaseQuery) ||
                groupName.contains(lowercaseQuery) ||
                participantNames.contains(lowercaseQuery);
          }).toList();

      setState(() {
        _filteredConversations = filtered;
      });
    }
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

  // Mark a conversation as read locally (update UI immediately)
  void markConversationAsRead(int conversationId) {
    if (!mounted) return;

    setState(() {
      // Update main conversations list
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index >= 0) {
        final conversation = _conversations[index];
        _conversations[index] = DMConversation(
          id: conversation.id,
          user1Id: conversation.user1Id,
          user2Id: conversation.user2Id,
          familyContextId: conversation.familyContextId,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          otherUserName: conversation.otherUserName,
          otherUserPhoto: conversation.otherUserPhoto,
          otherUserFirstName: conversation.otherUserFirstName,
          otherUserLastName: conversation.otherUserLastName,
          lastMessageContent: conversation.lastMessageContent,
          lastMessageTime: conversation.lastMessageTime,
          lastMessageSenderId: conversation.lastMessageSenderId,
          hasUnreadMessages: false, // Mark as read
          unreadCount: 0, // Clear unread count
          isGroup: conversation.isGroup,
          name: conversation.name,
          participantCount: conversation.participantCount,
          createdBy: conversation.createdBy,
          participants: conversation.participants,
        );
      }

      // Update filtered conversations list
      final filteredIndex = _filteredConversations.indexWhere(
        (c) => c.id == conversationId,
      );
      if (filteredIndex >= 0) {
        _filteredConversations[filteredIndex] = _conversations[index];
      }
    });

    debugPrint(
      '✅ MESSAGES_HOME: Marked conversation $conversationId as read locally',
    );
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
            FutureBuilder<Map<String, dynamic>?>(
              future:
                  Provider.of<ApiService>(
                    context,
                    listen: false,
                  ).getCurrentUser(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  final user = snapshot.data!;
                  final firstName = user['firstName'] as String? ?? '';
                  final lastName = user['lastName'] as String? ?? '';
                  final photo = user['photo'] as String?;
                  final userRole = user['role'] as String? ?? 'USER';
                  final initials = GroupAvatarUtils.getInitials(
                    firstName,
                    lastName,
                    user['username'] as String?,
                  );

                  return GestureDetector(
                    onTap: () {
                      // Navigate to user profile/settings
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => ProfileScreen(
                                userId: widget.userId,
                                userRole: userRole,
                              ),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: GroupAvatarUtils.getAvatarColor(
                        initials,
                      ),
                      child:
                          photo != null && photo.isNotEmpty
                              ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl:
                                      photo.startsWith('http')
                                          ? photo
                                          : '${Provider.of<ApiService>(context, listen: false).mediaBaseUrl}$photo',
                                  fit: BoxFit.cover,
                                  width: 36,
                                  height: 36,
                                  placeholder:
                                      (context, url) => Text(
                                        initials,
                                        style: TextStyle(
                                          color: GroupAvatarUtils.getTextColor(
                                            GroupAvatarUtils.getAvatarColor(
                                              initials,
                                            ),
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                  errorWidget:
                                      (context, url, error) => Text(
                                        initials,
                                        style: TextStyle(
                                          color: GroupAvatarUtils.getTextColor(
                                            GroupAvatarUtils.getAvatarColor(
                                              initials,
                                            ),
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                ),
                              )
                              : Text(
                                initials,
                                style: TextStyle(
                                  color: GroupAvatarUtils.getTextColor(
                                    GroupAvatarUtils.getAvatarColor(initials),
                                  ),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                    ),
                  );
                }

                // Fallback while loading - not tappable during loading
                return CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.lightGreen.shade100,
                  child: Text(
                    'U',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
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
    final lastMessageContent = conversation.lastMessageContent;
    final lastMessageTime = conversation.lastMessageTime;
    final unreadCount = conversation.unreadCount ?? 0;
    final conversationId = conversation.id;
    final bool hasUnread = conversation.hasUnreadMessages ?? false;

    String displayName;
    Widget leadingWidget;

    if (conversation.isGroup) {
      // Group chat display
      displayName = conversation.name ?? 'Group Chat';
      leadingWidget = GroupAvatarUtils.buildGroupAvatar(
        conversation.participants,
        Provider.of<ApiService>(context, listen: false),
        onTap: () {
          debugPrint(
            '🔧 Group avatar tapped for conversation ${conversation.id}',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => GroupManagementScreen(
                    conversationId: conversation.id,
                    groupName: conversation.name ?? 'Group Chat',
                    currentUserId: widget.userId,
                    participants: conversation.participants ?? [],
                  ),
            ),
          );
        },
      );
    } else {
      // 1:1 chat display (existing logic)
      final otherUserPhoto = conversation.otherUserPhoto;
      displayName = conversation.getOtherUserDisplayName();
      final String initials = conversation.getOtherUserInitials();
      leadingWidget = _buildAvatar(otherUserPhoto, initials, hasUnread);
    }

    final String timestamp = _formatTimestamp(lastMessageTime);

    // Determine what to show as the last message (no suffix for groups)
    String messagePreview;
    if (lastMessageContent != null && lastMessageContent.isNotEmpty) {
      messagePreview = lastMessageContent;
    } else {
      messagePreview =
          conversation.isGroup ? 'No messages yet' : 'No messages yet';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: leadingWidget,
        title: Row(
          children: [
            // Group icon for group chats
            if (conversation.isGroup) ...[
              Icon(Icons.group, size: 16, color: Colors.white.withOpacity(0.7)),
              const SizedBox(width: 4),
            ],
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
              otherUserId:
                  conversation.isGroup
                      ? 0
                      : conversation.getOtherUserId(widget.userId),
              otherUserName: displayName,
              otherUserPhoto:
                  conversation.isGroup ? null : conversation.otherUserPhoto,
              conversationId: conversationId,
              isGroup: conversation.isGroup,
              participantCount: conversation.participantCount,
              participants: conversation.participants,
              onMarkAsRead: () => _markConversationAsRead(conversationId),
            ),
          );
        },
      ),
    );
  }

  // Google Messages-style avatar colors
  static const List<Color> _avatarColors = [
    Color(0xFFFDD835), // Yellow
    Color(0xFF8E24AA), // Purple
    Color(0xFF42A5F5), // Light blue
    Color(0xFF66BB6A), // Green
    Color(0xFFFF7043), // Orange
    Color(0xFFEC407A), // Pink
    Color(0xFF26A69A), // Teal
    Color(0xFF5C6BC0), // Indigo
  ];

  // Get avatar color based on name (consistent per user)
  Color _getAvatarColor(String name) {
    // Get first letter and map to color index (A=0, B=1, etc.)
    if (name.isEmpty) return _avatarColors[0];

    final firstLetter = name[0].toUpperCase();
    final letterIndex = firstLetter.codeUnitAt(0) - 'A'.codeUnitAt(0);

    // Map letters A-Z to our 8 colors (repeating pattern)
    final colorIndex = letterIndex % _avatarColors.length;
    return _avatarColors[colorIndex];
  }

  // Get text color based on background color
  Color _getTextColor(Color backgroundColor) {
    // Use black text for yellow, white for others
    if (backgroundColor == const Color(0xFFFDD835)) {
      // Yellow
      return Colors.black;
    }
    return Colors.white;
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
        backgroundColor: _getAvatarColor(initials),
        child:
            photoUrl != null && photoUrl.isNotEmpty
                ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl:
                        photoUrl.startsWith('http')
                            ? photoUrl
                            : '${apiService.mediaBaseUrl}$photoUrl',
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    placeholder:
                        (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) {
                      final avatarColor = _getAvatarColor(initials);
                      return Text(
                        initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: _getTextColor(avatarColor),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      );
                    },
                  ),
                )
                : Text(
                  initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: _getTextColor(_getAvatarColor(initials)),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
      ),
    );
  }

  Widget _buildGroupAvatar(DMConversation conversation, ApiService apiService) {
    final participants = conversation.participants;

    Widget avatarWidget;

    if (participants != null && participants.isNotEmpty) {
      // Special case for single participant - center it
      if (participants.length == 1) {
        avatarWidget = SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: ClipOval(
                child: _buildParticipantAvatar(
                  participants[0],
                  apiService,
                  isSmall: false, // Use full size for single avatar
                ),
              ),
            ),
          ),
        );
      } else {
        // Google Messages style: max 4 avatars in corners for multiple participants
        avatarWidget = SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            children: [
              // First participant (top-left)
              if (participants.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: _buildParticipantAvatar(
                        participants[0],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
              // Second participant (bottom-right)
              if (participants.length > 1)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: _buildParticipantAvatar(
                        participants[1],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
              // Third participant (top-right)
              if (participants.length > 2)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: _buildParticipantAvatar(
                        participants[2],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
              // Fourth participant (bottom-left)
              if (participants.length > 3)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: _buildParticipantAvatar(
                        participants[3],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    } else {
      // Fallback to simple group avatar
      avatarWidget = CircleAvatar(
        radius: 24,
        backgroundColor: Colors.deepPurple.shade400,
        child: const Icon(Icons.group, color: Colors.white, size: 24),
      );
    }

    // Wrap with GestureDetector for group management navigation
    return GestureDetector(
      onTap: () {
        debugPrint(
          '🔧 Group avatar tapped for conversation ${conversation.id}',
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => GroupManagementScreen(
                  conversationId: conversation.id,
                  groupName: conversation.name ?? 'Group Chat',
                  currentUserId: widget.userId,
                  participants: conversation.participants ?? [],
                ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
        ),
        child: avatarWidget,
      ),
    );
  }

  Widget _buildParticipantAvatar(
    Map<String, dynamic> participant,
    ApiService apiService, {
    bool isSmall = false,
  }) {
    final photoUrl = participant['photo'] as String?;
    final firstName = participant['first_name'] as String? ?? '';
    final lastName = participant['last_name'] as String? ?? '';
    final username = participant['username'] as String? ?? '';

    final initials = _getInitials(firstName, lastName, username);
    final size = isSmall ? 12.0 : 16.0;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      final fullUrl =
          photoUrl.startsWith('http')
              ? photoUrl
              : '${apiService.mediaBaseUrl}$photoUrl';

      return CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => Container(
              color: Colors.grey.shade300,
              child: Icon(Icons.person, size: size, color: Colors.grey),
            ),
        errorWidget: (context, url, error) {
          final avatarColor = _getAvatarColor(initials);
          return CircleAvatar(
            backgroundColor: avatarColor,
            child: Text(
              initials,
              style: TextStyle(
                color: _getTextColor(avatarColor),
                fontWeight: FontWeight.bold,
                fontSize: isSmall ? 8 : 12,
              ),
            ),
          );
        },
      );
    }

    // No photo, show initials
    final avatarColor = _getAvatarColor(initials);
    return CircleAvatar(
      backgroundColor: avatarColor,
      child: Text(
        initials,
        style: TextStyle(
          color: _getTextColor(avatarColor),
          fontWeight: FontWeight.bold,
          fontSize: isSmall ? 8 : 12,
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
      '/topic/dm-list/${widget.userId}',
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

      // Check message type
      final messageType = data['type'] as String?;

      if (messageType == 'new_conversation') {
        // Handle new conversation notification
        debugPrint(
          '🆕 MESSAGES_HOME: New conversation created, refreshing list...',
        );
        _loadConversations();
        return;
      } else if (messageType != null && messageType != 'DM_MESSAGE') {
        debugPrint(
          '⚠️ MESSAGES_HOME: Unknown message type: $messageType, ignoring',
        );
        return;
      }

      final message = DMMessage.fromJson(data);
      debugPrint('📨 MESSAGES_HOME: Parsed message: ${message.content}');

      // Skip messages sent by current user - they're handled by the callback
      if (message.senderId == widget.userId) {
        debugPrint(
          '📨 MESSAGES_HOME: Skipping own message (handled by callback)',
        );
        return;
      }

      // Extract unread count from WebSocket data
      final unreadCount = data['unread_count'] as int?;
      debugPrint('📨 MESSAGES_HOME: Unread count from WebSocket: $unreadCount');

      // Update the conversation list with the new message and unread count
      _updateConversationWithNewMessage(message, unreadCount: unreadCount);
    } catch (e, stackTrace) {
      debugPrint('❌ MESSAGES_HOME: Error handling WebSocket message: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Mark a conversation as read (clear unread count) - called via callback
  void _markConversationAsRead(int conversationId) {
    if (!mounted) return;

    setState(() {
      // Find and update the conversation in the main list
      for (int i = 0; i < _conversations.length; i++) {
        if (_conversations[i].id == conversationId) {
          final conv = _conversations[i];
          _conversations[i] = DMConversation(
            id: conv.id,
            user1Id: conv.user1Id,
            user2Id: conv.user2Id,
            familyContextId: conv.familyContextId,
            createdAt: conv.createdAt,
            updatedAt: conv.updatedAt,
            otherUserName: conv.otherUserName,
            otherUserPhoto: conv.otherUserPhoto,
            otherUserFirstName: conv.otherUserFirstName,
            otherUserLastName: conv.otherUserLastName,
            lastMessageContent: conv.lastMessageContent,
            lastMessageTime: conv.lastMessageTime,
            lastMessageSenderId: conv.lastMessageSenderId,
            hasUnreadMessages: false, // Clear unread flag
            unreadCount: 0, // Clear unread count
            isGroup: conv.isGroup,
            name: conv.name,
            participantCount: conv.participantCount,
            createdBy: conv.createdBy,
            participants: conv.participants,
          );
          break;
        }
      }

      // Update filtered list to match current search
      _filteredConversations = List.from(_conversations);
    });

    debugPrint(
      '✅ MESSAGES_HOME: Cleared unread count for conversation $conversationId',
    );
  }

  // Update conversation list when new message arrives
  void _updateConversationWithNewMessage(
    DMMessage message, {
    int? unreadCount,
  }) {
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
          hasUnreadMessages: unreadCount != null ? unreadCount > 0 : false,
          unreadCount: unreadCount ?? 0, // Use the count from WebSocket
          // Preserve group chat fields
          isGroup: conversation.isGroup,
          name: conversation.name,
          participantCount: conversation.participantCount,
          createdBy: conversation.createdBy,
          participants: conversation.participants,
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
          '✅ MESSAGES_HOME: Updated conversation ${message.conversationId} with unread count: $unreadCount',
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
