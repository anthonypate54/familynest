import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../services/api_service.dart';
import '../widgets/user_avatar.dart';

import '../services/websocket_service.dart';
import '../models/dm_conversation.dart';
import '../models/dm_message.dart';
import '../theme/app_theme.dart';

import '../utils/page_transitions.dart';
import '../utils/avatar_utils.dart';
import 'message_search_screen.dart';
import 'choose_dm_recipient_screen.dart';
import 'dm_thread_screen.dart';
import 'group_management_screen.dart';

import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/family_management_screen.dart';

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

      // Check if we were opened from a notification with a target conversation
      _checkForTargetConversation();
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
      debugPrint('Returned to MessagesHomeScreen, refreshing conversations...');
      _hasNavigatedAway = false;
      _loadConversations();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        'App resumed, checking WebSocket and refreshing conversations on MessagesHomeScreen...',
      );

      // Ensure WebSocket is connected and subscriptions are active
      if (_webSocketService != null) {
        if (!_webSocketService!.isConnected) {
          debugPrint('WebSocket not connected, reconnecting...');
          _webSocketService!.initialize().then((_) {
            // Re-establish subscription after connection
            _ensureWebSocketSubscription();
          });
        } else {
          // WebSocket is connected, ensure our subscription is active
          _ensureWebSocketSubscription();
        }
      }

      // Check if we need to force refresh due to notification
      _checkForceRefresh();
    }
  }

  /// Check if we need to force refresh due to notification
  Future<void> _checkForceRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shouldForceRefresh =
          prefs.getBool('force_refresh_on_resume') ?? false;

      if (shouldForceRefresh) {
        debugPrint('🔄 Force refreshing conversations due to notification');

        // Clear the flag
        await prefs.setBool('force_refresh_on_resume', false);

        // Check for simulated WebSocket message from notification
        final simulatedMessageJson = prefs.getString(
          'simulated_websocket_message',
        );
        if (simulatedMessageJson != null) {
          debugPrint('📱 Found simulated WebSocket message from notification');

          try {
            // Parse the simulated message
            final simulatedMessage =
                jsonDecode(simulatedMessageJson) as Map<String, dynamic>;

            // Process it as if it came from WebSocket
            if (simulatedMessage['type'] == 'DM_MESSAGE') {
              // We don't need to create a DMMessage object here
              // since we're passing the raw message to _handleIncomingDMMessage

              // Process using existing WebSocket handler
              _handleIncomingDMMessage(simulatedMessage);

              // Clear the simulated message
              await prefs.remove('simulated_websocket_message');
            }
          } catch (e) {
            debugPrint('Error processing simulated message: $e');
          }
        }

        // Load conversations with force refresh
        _loadConversations();
      } else {
        // Normal refresh
        _loadConversations();
      }
    } catch (e) {
      debugPrint('Error checking force refresh: $e');
      // Fall back to normal refresh
      _loadConversations();
    }
  }

  // This method is no longer used since we're using the simulated WebSocket approach
  // It's kept for reference in case we need to revert to the direct navigation approach

  /// Check if we were opened from a notification with a target conversation
  void _checkForTargetConversation() {
    try {
      // Check if we have route arguments with a target conversation
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final targetConversationId = args['targetConversationId'];
        if (targetConversationId != null) {
          debugPrint(
            '🎯 Target conversation ID from notification: $targetConversationId',
          );

          // Navigate to this conversation
          _navigateToConversation(targetConversationId.toString());
        }
      }
    } catch (e) {
      debugPrint('Error checking for target conversation: $e');
    }
  }

  /// Navigate to conversation detail screen
  void _navigateToConversationDetail(DMConversation conversation) {
    // Navigate to the DM thread screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => DMThreadScreen(
              currentUserId: widget.userId,
              otherUserId: conversation.user2Id ?? 0,
              otherUserName: conversation.getOtherUserDisplayName(),
              otherUserPhoto: conversation.otherUserPhoto,
              conversationId: conversation.id,
              isGroup: conversation.isGroup,
              participantCount: conversation.participantCount,
              participants: conversation.participants,
              onMarkAsRead: () => _markConversationAsRead(conversation.id),
            ),
      ),
    );
  }

  /// Navigate to a specific conversation by ID
  void _navigateToConversation(String conversationId) {
    try {
      // Find the conversation in our list
      final convoId = int.tryParse(conversationId);
      if (convoId == null) return;

      // Find the conversation
      DMConversation? conversation;
      try {
        conversation = _conversations.firstWhere((c) => c.id == convoId);
      } catch (e) {
        conversation = null;
      }

      if (conversation != null) {
        debugPrint('🧭 Navigating to conversation: ${conversation.id}');
        _navigateToConversationDetail(conversation);
      } else {
        // If conversation not found, force a refresh and try again
        debugPrint('⚠️ Conversation not found, refreshing data...');
        _loadConversations().then((_) {
          // Try again after refresh
          DMConversation? refreshedConversation;
          try {
            refreshedConversation = _conversations.firstWhere(
              (c) => c.id == convoId,
            );
          } catch (e) {
            refreshedConversation = null;
          }

          if (refreshedConversation != null) {
            _navigateToConversationDetail(refreshedConversation);
          }
        });
      }
    } catch (e) {
      debugPrint('Error navigating to conversation: $e');
    }
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
      debugPrint('Loaded ${conversations.length} conversations');
      for (int i = 0; i < conversations.length; i++) {
        final conv = conversations[i];
        debugPrint(
          '${conv.otherUserName} - "${conv.lastMessageContent}" - ${conv.lastMessageTime}',
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
      debugPrint('Error loading conversations: $e');

      // Check if it's an authentication error
      if (e.toString().contains('403') ||
          e.toString().contains('401') ||
          e.toString().contains('Invalid token') ||
          e.toString().contains('Session expired')) {
        debugPrint('🔒 Authentication error detected, redirecting to login');
        _redirectToLogin();
        return;
      }

      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // Redirect to login on authentication errors
  void _redirectToLogin() {
    if (!mounted) return;
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false, // Remove all previous routes
      );
    });
  }

  void _filterConversations(String query) async {
    debugPrint('_filterConversations called with query: "$query"');
    final lowercaseQuery = query.toLowerCase();

    if (query.isEmpty) {
      debugPrint('Query is empty, showing all conversations');
      setState(() {
        _filteredConversations =
            _conversations; // Show all conversations when query is empty
      });
      return;
    }

    debugPrint('About to call backend search...');
    try {
      // Use backend search for comprehensive results
      final apiService = Provider.of<ApiService>(context, listen: false);
      debugPrint('Got apiService, calling searchDMConversations...');
      final searchResults = await apiService.searchDMConversations(query);

      setState(() {
        _filteredConversations = searchResults;
      });

      debugPrint('found ${searchResults.length} results for "$query"');
    } catch (e) {
      debugPrint('$e');
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

  void _goToFamilyManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FamilyManagementScreen(userId: widget.userId),
      ),
    );
  }

  Widget _buildEmptyConversationsState() {
    return FutureBuilder<Map<String, dynamic>?>(
      future:
          Provider.of<ApiService>(
            context,
            listen: false,
          ).getCompleteFamilyData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        // Parse family data to determine the appropriate message
        String title = 'No conversations yet';
        String subtitle = 'Start a new conversation';
        String buttonText = 'Start a new conversation';
        bool canStartConversation = true;
        bool shouldGoToFamilyManagement = false;

        if (snapshot.hasData && snapshot.data != null) {
          final familiesData =
              snapshot.data!['families'] as List<dynamic>? ?? [];

          if (familiesData.isEmpty) {
            // User has no families
            title = 'No family members to chat with';
            subtitle =
                'Create a family or accept an invitation to start messaging your family members';
            buttonText = 'Go to Family Management';
            canStartConversation = false;
            shouldGoToFamilyManagement = true;
          } else {
            // User has families, check if they have other members
            int totalOtherMembers = 0;
            for (var family in familiesData) {
              final members = family['members'] as List<dynamic>? ?? [];
              // Count members excluding the current user
              totalOtherMembers +=
                  members
                      .where((member) => member['userId'] != widget.userId)
                      .length;
            }

            if (totalOtherMembers == 0) {
              // User has families but no other members
              title = 'No family members to chat with';
              subtitle = 'Invite family members to start having conversations';
              buttonText = 'Invite family members';
              canStartConversation = false;
              shouldGoToFamilyManagement = true;
            } else {
              // User has family members but no conversations yet
              title = 'No conversations yet';
              subtitle = 'Start chatting with your family members';
              buttonText = 'Start a new conversation';
              canStartConversation = true;
              shouldGoToFamilyManagement = false;
            }
          }
        }

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed:
                    canStartConversation
                        ? _startNewConversation
                        : shouldGoToFamilyManagement
                        ? _goToFamilyManagement
                        : null,
                style: TextButton.styleFrom(
                  foregroundColor:
                      canStartConversation ? Colors.white : Colors.white70,
                ),
                child: Text(buttonText, style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        );
      },
    );
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

    debugPrint('Marked conversation $conversationId as read locally');
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
            const Icon(
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
                // Navigate to DM search screen
                slidePush(
                  context,
                  MessageSearchScreen(
                    userId: widget.userId,
                    isDMSearch: true, // Search DM conversations
                  ),
                );
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

                  // Calculate initials using same logic as UserAvatar
                  String initials = '';
                  if (firstName.isNotEmpty) {
                    initials += firstName[0].toUpperCase();
                  }
                  if (lastName.isNotEmpty) {
                    initials += lastName[0].toUpperCase();
                  }
                  if (initials.isEmpty && user['username'] != null) {
                    final username = user['username'] as String;
                    if (username.isNotEmpty) {
                      initials = username[0].toUpperCase();
                    }
                  }

                  return UserAvatar(
                    photoUrl: photo,
                    firstName: firstName,
                    lastName: lastName,
                    displayName: initials,
                    radius: 18,
                    fontSize: 14,
                    useFirstInitialOnly: true,
                  );
                }

                // Fallback while loading - not tappable during loading
                return const UserAvatar(displayName: 'U', radius: 18);
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
                      ? _buildEmptyConversationsState()
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
      floatingActionButton: FutureBuilder<Map<String, dynamic>?>(
        future:
            Provider.of<ApiService>(
              context,
              listen: false,
            ).getCompleteFamilyData(),
        builder: (context, snapshot) {
          // While loading, show the button (default behavior)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return FloatingActionButton(
              onPressed: _startNewConversation,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.message, color: Colors.white),
            );
          }

          // Determine if user has family members to chat with
          bool hasFamilyMembersToChat = false;

          if (snapshot.hasData && snapshot.data != null) {
            final familiesData =
                snapshot.data!['families'] as List<dynamic>? ?? [];

            if (familiesData.isNotEmpty) {
              // Check if user has other family members
              int totalOtherMembers = 0;
              for (var family in familiesData) {
                final members = family['members'] as List<dynamic>? ?? [];
                // Count members excluding the current user
                totalOtherMembers +=
                    members
                        .where((member) => member['userId'] != widget.userId)
                        .length;
              }
              hasFamilyMembersToChat = totalOtherMembers > 0;
            }
          }

          // Only show FAB if user has family members to chat with
          return hasFamilyMembersToChat
              ? FloatingActionButton(
                onPressed: _startNewConversation,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.message, color: Colors.white),
              )
              : const SizedBox.shrink(); // Hidden FAB
        },
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

      // 🐛 DEBUG: Check participant data for group avatars
      debugPrint('GROUP AVATAR DEBUG for "$displayName":');
      debugPrint(
        '  - Participants count: ${conversation.participants?.length ?? 0}',
      );
      if (conversation.participants != null) {
        for (int i = 0; i < conversation.participants!.length; i++) {
          final p = conversation.participants![i];
          debugPrint(
            '  - Participant $i: first_name="${p['first_name']}", last_name="${p['last_name']}", photo="${p['photo']}"',
          );
        }
      }

      leadingWidget = AvatarUtils.buildGroupAvatar(
        participants: conversation.participants,
        hasUnread: hasUnread,
        radius: 24,
        fontSize: 18,
        onTap: () => _navigateToGroupManagement(conversation),
      );
    } else {
      // 1:1 chat display (existing logic)
      final otherUserPhoto = conversation.otherUserPhoto;
      displayName = conversation.getOtherUserDisplayName();
      debugPrint('###Other User Photo: $otherUserPhoto');
      leadingWidget = _buildAvatar(
        otherUserPhoto,
        conversation.otherUserFirstName,
        conversation.otherUserLastName,
        hasUnread,
      );
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
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: leadingWidget,
        // onTap is handled at the end of this ListTile
        title: Row(
          children: [
            // Group icon for group chats
            if (conversation.isGroup) ...[
              Icon(
                Icons.group,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
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
                      hasUnread
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
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
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.7),
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
          _hasNavigatedAway = true;
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

  Widget _buildAvatar(
    String? photoUrl,
    String? firstName,
    String? lastName,
    bool hasUnread,
  ) {
    // 🐛 DEBUG: Log what name Messages screen uses for color hashing
    debugPrint(
      'MessagesScreen avatar - firstName: "$firstName", lastName: "$lastName"',
    );

    return AvatarUtils.buildUserAvatar(
      photoUrl: photoUrl,
      firstName: firstName,
      lastName: lastName,
      radius: 24,
      fontSize: 18,
      hasUnread: hasUnread,
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
              // Update UI if needed based on connection status
            });
          }
        });
      }
    };

    // Subscribe to DM messages for this user
    _ensureWebSocketSubscription();

    // Listen for connection status changes
    _webSocketService!.addConnectionListener(_connectionListener!);

    // Initialize WebSocket connection if not already connected
    _webSocketService!.initialize();
  }

  // Ensure WebSocket subscription is active (can be called multiple times safely)
  void _ensureWebSocketSubscription() {
    if (_webSocketService == null || _dmMessageHandler == null) return;

    debugPrint('Ensuring WebSocket subscription for user ${widget.userId}');

    // Subscribe to DM messages for this user (WebSocketService handles duplicates)
    _webSocketService!.subscribe(
      '/topic/dm-list/${widget.userId}',
      _dmMessageHandler!,
    );
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
        debugPrint('Unknown message type: $messageType, ignoring');
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
      debugPrint('Error handling WebSocket message: $e');
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

    debugPrint('Cleared unread count for conversation $conversationId');
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
          'Updated conversation ${message.conversationId} with unread count: $unreadCount',
        );
      } else {
        debugPrint(
          'Conversation ${message.conversationId} not found, refreshing list',
        );
        // If conversation not found, refresh the entire list
        _loadConversations();
      }
    });
  }

  // Helper method to navigate to group management
  void _navigateToGroupManagement(DMConversation conversation) {
    debugPrint('🔧 Group avatar tapped for conversation ${conversation.id}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => GroupManagementScreen(
              conversationId: conversation.id,
              groupName: conversation.name ?? 'Group Chat',
              currentUserId: widget.userId,
              participants: conversation.participants ?? [],
              onParticipantsChanged: () {
                debugPrint(
                  'Group participants changed, refreshing conversation list',
                );
                _loadConversations();
              },
            ),
      ),
    );
  }
}
