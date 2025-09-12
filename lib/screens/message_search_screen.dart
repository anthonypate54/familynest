import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../utils/page_transitions.dart';
import 'dart:async';
import '../widgets/gradient_background.dart';
import '../widgets/user_avatar.dart';
import 'dm_thread_screen.dart'; // Import DMThreadScreen
import '../models/dm_conversation.dart'; // Import DMConversation model
import '../theme/app_theme.dart';
import '../utils/group_avatar_utils.dart'; // Import the shared utility

class MessageSearchScreen extends StatefulWidget {
  final int userId;
  final bool isDMSearch; // true for DM search, false for Family News search

  const MessageSearchScreen({
    super.key,
    required this.userId,
    this.isDMSearch = false, // Default to Family News search
  });

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _families = [];
  int? _selectedFamilyId;
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadFamilies();
    _searchController.addListener(_onSearchChanged);

    // Test the search controller endpoint
    _testSearchController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFamilies() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final families = await apiService.getSearchFamilies();

      if (mounted) {
        setState(() {
          _families = families;
        });
      }
    } catch (e) {
      debugPrint('Error loading families: $e');
    }
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();

    final query = _searchController.text.trim();

    if (query.length < 3) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    // Debounce search for 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 3) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);

      List<Map<String, dynamic>> results;
      if (widget.isDMSearch) {
        // Search DM conversations
        final dmConversations = await apiService.searchDMConversations(query);
        // Convert DMConversation objects to Map format for consistency
        results =
            dmConversations
                .map(
                  (conv) => {
                    'id': conv.id,
                    'is_group': conv.isGroup,
                    'name': conv.name,
                    'other_user_name': conv.otherUserName,
                    'other_user_photo': conv.otherUserPhoto,
                    'user1_id': conv.user1Id,
                    'user2_id': conv.user2Id,
                    'last_message_content': conv.lastMessageContent,
                    'last_message_time':
                        conv.lastMessageTime?.toIso8601String(),
                    'participant_count': conv.participantCount,
                    'message_type': 'dm_conversation',
                  },
                )
                .toList();
      } else {
        // Search family messages
        results = await apiService.searchMessages(
          query: query,
          familyId: _selectedFamilyId,
        );
      }

      debugPrint('$results');
      if (results.isNotEmpty) {
        debugPrint('${results.first.keys.toList()}');
        debugPrint('${results.first}');
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error performing search: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToMessage(Map<String, dynamic> message) {
    debugPrint('$message');

    if (widget.isDMSearch) {
      // DM search result - navigate to DM conversation
      final conversationId = message['id'] as int?;
      if (conversationId != null) {
        debugPrint('$conversationId');
        _navigateToDMConversation(message);
      }
    } else {
      // Family message search result - navigate to specific message
      final messageId = message['id'] as int?;
      final senderId = message['sender_id'] as int?;

      debugPrint('$messageId, senderId: $senderId');

      if (messageId != null && senderId != null) {
        debugPrint(
          '$messageId, senderId: $senderId',
        );
        _navigateToDMThread(message);
      } else {
        debugPrint('Cannot navigate - messageId or senderId is null');
      }
    }
  }

  // Helper method to navigate to DM thread
  Future<void> _navigateToDMThread(Map<String, dynamic> message) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Get the sender ID and conversation ID from the message
      final senderId = message['sender_id'] as int?;
      final conversationId = message['conversation_id'] as int?;

      if (senderId == null) {
        debugPrint('Cannot navigate to DM - sender_id is null');
        return;
      }

      if (conversationId == null) {
        debugPrint('Cannot navigate to DM - conversation_id is null');
        return;
      }

      // Get the conversation details
      final conversations = await apiService.getDMConversations();
      DMConversation? conversation;

      try {
        conversation = conversations.firstWhere(
          (conv) => conv.id == conversationId,
        );
      } catch (e) {
        // Conversation not found, use first one as fallback
        if (conversations.isNotEmpty) {
          conversation = conversations.first;
        }
      }

      if (conversation == null) {
        debugPrint('$conversationId');
        return;
      }

      // Determine the other user ID (use helper method that handles nulls and groups)
      final otherUserId = conversation.getOtherUserId(widget.userId);

      debugPrint(
        '${conversation.id}, otherUserId: $otherUserId, isGroup: ${conversation.isGroup}',
      );

      // Navigate to DM thread screen
      if (!mounted) return;
      slidePushReplacement(
        context,
        DMThreadScreen(
          currentUserId: widget.userId,
          otherUserId: otherUserId,
          otherUserName: conversation.otherUserName ?? 'Unknown User',
          otherUserPhoto: conversation.otherUserPhoto ?? '',
          conversationId: conversation.id,
          isGroup: conversation.isGroup,
          participantCount: conversation.participantCount,
          participants: conversation.participants,
        ),
      );
    } catch (e) {
      debugPrint('$e');
      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to navigate to DM conversation (for DM search results)
  Future<void> _navigateToDMConversation(
    Map<String, dynamic> conversation,
  ) async {
    try {
      final conversationId = conversation['id'] as int;
      final isGroup = conversation['is_group'] as bool? ?? false;

      if (isGroup) {
        // Group conversation
        final groupName = conversation['name'] as String? ?? 'Group Chat';
        final participantCount = conversation['participant_count'] as int? ?? 2;

        slidePushReplacement(
          context,
          DMThreadScreen(
            currentUserId: widget.userId,
            otherUserId: 0, // Not applicable for groups
            otherUserName: groupName,
            otherUserPhoto: '',
            conversationId: conversationId,
            isGroup: true,
            participantCount: participantCount,
            participants: [], // Will be loaded in DMThreadScreen
          ),
        );
      } else {
        // 1:1 conversation
        final otherUserName =
            conversation['other_user_name'] as String? ?? 'Unknown User';
        final otherUserPhoto =
            conversation['other_user_photo'] as String? ?? '';

        // For 1:1 conversations, determine the other user ID
        final user1Id = conversation['user1_id'] as int?;
        final user2Id = conversation['user2_id'] as int?;
        final otherUserId = (user1Id == widget.userId) ? user2Id : user1Id;

        slidePushReplacement(
          context,
          DMThreadScreen(
            currentUserId: widget.userId,
            otherUserId: otherUserId ?? 0,
            otherUserName: otherUserName,
            otherUserPhoto: otherUserPhoto,
            conversationId: conversationId,
            isGroup: false,
            participantCount: 2,
            participants: [],
          ),
        );
      }
    } catch (e) {
      debugPrint('$e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open conversation')),
      );
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';

    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        return days[dateTime.weekday - 1];
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'Now';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildSenderAvatar(
    String? senderPhoto,
    String? firstName,
    String? lastName,
    String? username,
  ) {
    final initials = GroupAvatarUtils.getInitials(
      firstName,
      lastName,
      username,
    );

    return UserAvatar(
      photoUrl: senderPhoto,
      firstName: firstName,
      lastName: lastName,
      displayName: initials,
      radius: 20,
      fontSize: 16,
      useFirstInitialOnly: true,
    );
  }

  String _getSenderDisplayName(Map<String, dynamic> message) {
    final senderFirstName = message['sender_first_name']?.toString();
    final senderLastName = message['sender_last_name']?.toString();
    final senderUsername = message['sender_username']?.toString();

    if (senderFirstName != null && senderLastName != null) {
      return '$senderFirstName $senderLastName';
    } else if (senderUsername != null) {
      return senderUsername;
    } else {
      return 'Unknown User';
    }
  }

  Future<void> _testSearchController() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final result = await apiService.testSearchController();
      if (result != null) {
        debugPrint('${result['message']}');
      } else {
        debugPrint('Search controller test failed');
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        elevation: 0,
        title: Text(
          widget.isDMSearch ? 'Search Messages' : 'Search Family News',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        // No actions needed for search screen
      ),
      body: GradientBackground(
        child: Column(
          children: [
            // Search bar and filters
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Search text field
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          widget.isDMSearch
                              ? 'Search messages...'
                              : 'Search Family News...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Family filter dropdown
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedFamilyId,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).colorScheme.primary,
                        style: const TextStyle(color: Colors.white),
                        hint: const Text(
                          'All Families',
                          style: TextStyle(color: Colors.white),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All Families',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          ..._families.map((family) {
                            return DropdownMenuItem<int?>(
                              value: family['family_id'] as int?,
                              child: Text(
                                family['family_name'] as String? ??
                                    'Unknown Family',
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (int? familyId) {
                          setState(() {
                            _selectedFamilyId = familyId;
                          });

                          // Re-search if we have a query
                          final query = _searchController.text.trim();
                          if (query.length >= 3) {
                            _performSearch(query);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search results
            Expanded(child: _buildSearchResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (!_hasSearched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Type at least 3 characters to search',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'No messages found',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final message = _searchResults[index];
        return _buildSearchResultItem(message);
      },
    );
  }

  Widget _buildSearchResultItem(Map<String, dynamic> message) {
    final content = message['content'] as String? ?? '';
    final senderName = _getSenderDisplayName(message);
    final familyName = message['family_name'] as String? ?? '';
    final timestamp = message['timestamp']?.toString();
    final senderPhoto = message['sender_photo'] as String?;
    final mediaType = message['media_type'] as String?;
    final mediaUrl = message['media_url'] as String?;

    // Check if this is a group chat message
    final isGroup = message['is_group'] as bool? ?? false;
    final conversationName = message['conversation_name'] as String?;
    final participants = message['participants'] as List<dynamic>?;

    // Safely extract sender information with proper type casting
    final senderFirstName = message['sender_first_name']?.toString();
    final senderLastName = message['sender_last_name']?.toString();
    final senderUsername = message['sender_username']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.15,
        ), // Light green like MessagesHomeScreen
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          debugPrint('$message');
          _navigateToMessage(message);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with avatar info and timestamp
              Row(
                children: [
                  // Show group avatar for group chats, sender avatar for 1:1
                  isGroup
                      ? GroupAvatarUtils.buildGroupAvatar(
                        participants?.cast<Map<String, dynamic>>(),
                        Provider.of<ApiService>(context, listen: false),
                      )
                      : _buildSenderAvatar(
                        senderPhoto,
                        senderFirstName,
                        senderLastName,
                        senderUsername,
                      ),
                  const SizedBox(width: 12),

                  // Conversation name and message (2 lines like MessagesHomeScreen)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGroup
                              ? (conversationName ?? familyName)
                              : senderName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color:
                                Colors
                                    .white, // White text like MessagesHomeScreen
                          ),
                        ),
                        if (content.isNotEmpty)
                          Text(
                            content,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: 0.7,
                              ), // Light white like MessagesHomeScreen
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Timestamp
                  Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: 0.7,
                      ), // Light white like MessagesHomeScreen
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Media indicator (removed duplicate message content)
              if (mediaType != null && mediaUrl != null) ...[
                Row(
                  children: [
                    Icon(
                      mediaType == 'image' ? Icons.image : Icons.videocam,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mediaType == 'image' ? 'Photo' : 'Video',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
