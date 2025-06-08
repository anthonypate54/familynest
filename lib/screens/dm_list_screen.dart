import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/gradient_background.dart';
import 'dm_thread_screen.dart';
import '../utils/page_transitions.dart';

class DMListScreen extends StatefulWidget {
  final int userId;

  const DMListScreen({super.key, required this.userId});

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Search state
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _familyMembers = [];
  List<Map<String, dynamic>> _filteredMembers = [];
  List<Map<String, dynamic>> _filteredConversations = [];
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
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

  Future<void> _refreshConversations() async {
    await _loadConversations();
  }

  Future<void> _loadFamilyMembers() async {
    if (_loadingMembers) return;

    try {
      setState(() {
        _loadingMembers = true;
      });

      final apiService = Provider.of<ApiService>(context, listen: false);

      // Check if we have a token
      final members = await apiService.getFamilyMembers(widget.userId);

      // Filter out the current user
      final filteredMembers =
          members.where((member) {
            final memberId = member['userId'] as int?;
            final shouldInclude = memberId != null && memberId != widget.userId;
            return shouldInclude;
          }).toList();

      if (mounted) {
        setState(() {
          _familyMembers = filteredMembers;
          _filteredMembers = filteredMembers;
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMembers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading family members: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterMembers(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredMembers = _familyMembers;
        _filteredConversations = [];
      });
      return;
    }

    final lowercaseQuery = query.toLowerCase();

    // Filter existing conversations
    final filteredConversations =
        _conversations.where((conversation) {
          final otherFirstName =
              (conversation['other_first_name'] as String? ?? '').toLowerCase();
          final otherLastName =
              (conversation['other_last_name'] as String? ?? '').toLowerCase();
          final otherUsername =
              (conversation['other_username'] as String? ?? '').toLowerCase();

          return otherFirstName.contains(lowercaseQuery) ||
              otherLastName.contains(lowercaseQuery) ||
              otherUsername.contains(lowercaseQuery) ||
              '$otherFirstName $otherLastName'.contains(lowercaseQuery);
        }).toList();

    // Filter family members (for new conversations)
    final filteredMembers =
        _familyMembers.where((member) {
          final firstName =
              (member['firstName'] as String? ?? '').toLowerCase();
          final lastName = (member['lastName'] as String? ?? '').toLowerCase();
          final username = (member['username'] as String? ?? '').toLowerCase();

          return firstName.contains(lowercaseQuery) ||
              lastName.contains(lowercaseQuery) ||
              username.contains(lowercaseQuery) ||
              '$firstName $lastName'.contains(lowercaseQuery);
        }).toList();

    setState(() {
      _filteredConversations = filteredConversations;
      _filteredMembers = filteredMembers;
    });
  }

  Future<void> _startConversationWith(Map<String, dynamic> member) async {
    final memberId = member['userId'] as int?;
    if (memberId == null) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final apiService = Provider.of<ApiService>(context, listen: false);
      final conversationData = await apiService.getOrCreateConversation(
        memberId,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (conversationData != null) {
          final conversationId = conversationData['conversationId'] as int?;
          if (conversationId != null) {
            // Close search interface
            _closeSearch();

            // Build display name
            String displayName = '';
            final firstName = member['firstName'] as String?;
            final lastName = member['lastName'] as String?;
            final username = member['username'] as String?;

            if (firstName != null && firstName.isNotEmpty) {
              displayName = firstName;
              if (lastName != null && lastName.isNotEmpty) {
                displayName += ' $lastName';
              }
            } else if (username != null && username.isNotEmpty) {
              displayName = username;
            } else {
              displayName = 'Unknown User';
            }

            // Navigate to DM thread
            slidePush(
              context,
              DMThreadScreen(
                currentUserId: widget.userId,
                otherUserId: memberId,
                otherUserName: displayName,
                conversationId: conversationId,
              ),
            );

            // Refresh conversations list
            _refreshConversations();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create conversation'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _searchController.clear();
      _filteredMembers.clear();
      _filteredConversations.clear();
      _familyMembers.clear();
    });
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return '';

    final messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(messageTime);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  String _getInitials(String? firstName, String? lastName, String? username) {
    if (firstName != null && firstName.isNotEmpty) {
      final first = firstName[0].toUpperCase();
      final last =
          lastName != null && lastName.isNotEmpty
              ? lastName[0].toUpperCase()
              : '';
      return '$first$last';
    } else if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        title: const Text(
          'Direct Messages',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _refreshConversations,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: GradientBackground(
        child: Stack(
          children: [
            Column(
              children: [
                // Google Messages style search bar
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        if (value.isNotEmpty && !_showSearch) {
                          _showSearch = true;
                          _loadFamilyMembers();
                        } else if (value.isEmpty && _showSearch) {
                          _showSearch = false;
                        }
                      });
                      _filterMembers(value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Messages',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),

                // Conversation list
                Expanded(
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
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _refreshConversations,
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
                                Text(
                                  'No conversations yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Search for family members to start chatting',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          )
                          : Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                            ),
                            child: RefreshIndicator(
                              onRefresh: _refreshConversations,
                              child: ListView.builder(
                                padding: const EdgeInsets.only(top: 8),
                                itemCount: _conversations.length,
                                itemBuilder: (context, index) {
                                  final conversation = _conversations[index];
                                  return _buildConversationTile(conversation);
                                },
                              ),
                            ),
                          ),
                ),
              ],
            ),

            // Search overlay (when typing in search field)
            if (_showSearch) _buildSearchOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    // Extract conversation data from API response
    final otherUserId = conversation['other_user_id'] as int?;
    final otherUsername = conversation['other_username'] as String?;
    final otherFirstName = conversation['other_first_name'] as String?;
    final otherLastName = conversation['other_last_name'] as String?;
    final lastMessageContent = conversation['last_message_content'] as String?;
    final lastMessageTime = conversation['last_message_time'];
    final unreadCount = conversation['unread_count'] as int? ?? 0;
    final conversationId = conversation['conversation_id'] as int?;

    // Build display name
    String displayName = '';
    if (otherFirstName != null && otherFirstName.isNotEmpty) {
      displayName = otherFirstName;
      if (otherLastName != null && otherLastName.isNotEmpty) {
        displayName += ' $otherLastName';
      }
    } else if (otherUsername != null && otherUsername.isNotEmpty) {
      displayName = otherUsername;
    } else {
      displayName = 'Unknown User';
    }

    final bool hasUnread = unreadCount > 0;
    final String initials = _getInitials(
      otherFirstName,
      otherLastName,
      otherUsername,
    );
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
            if (hasUnread)
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
          if (otherUserId != null && conversationId != null) {
            // Navigate to DM thread screen with slide transition
            slidePush(
              context,
              DMThreadScreen(
                currentUserId: widget.userId,
                otherUserId: otherUserId,
                otherUserName: displayName,
                conversationId: conversationId,
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned(
      top: 80, // Position below the search bar
      left: 16,
      right: 16,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Start new conversation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Colors.grey.shade200),

            // Search results
            Expanded(
              child:
                  _loadingMembers
                      ? const Center(child: CircularProgressIndicator())
                      : _searchController.text.isEmpty
                      ? _buildInitialSearchState()
                      : (_filteredConversations.isEmpty &&
                          _filteredMembers.isEmpty)
                      ? _buildNoResultsState()
                      : ListView(
                        children: [
                          // Existing conversations
                          if (_filteredConversations.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'Conversations',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            ..._filteredConversations.map(
                              (conversation) =>
                                  _buildConversationSearchTile(conversation),
                            ),
                          ],

                          // New conversations
                          if (_filteredMembers.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'Start new conversation',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            ..._filteredMembers.map(
                              (member) => _buildMemberTile(member),
                            ),
                          ],
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialSearchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Type to search for family members',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No family members found for "${_searchController.text}"',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildConversationSearchTile(Map<String, dynamic> conversation) {
    // Extract conversation data from API response
    final otherUserId = conversation['other_user_id'] as int?;
    final otherUsername = conversation['other_username'] as String?;
    final otherFirstName = conversation['other_first_name'] as String?;
    final otherLastName = conversation['other_last_name'] as String?;
    final lastMessageContent = conversation['last_message_content'] as String?;
    final lastMessageTime = conversation['last_message_time'];
    final conversationId = conversation['conversation_id'] as int?;

    // Build display name
    String displayName = '';
    if (otherFirstName != null && otherFirstName.isNotEmpty) {
      displayName = otherFirstName;
      if (otherLastName != null && otherLastName.isNotEmpty) {
        displayName += ' $otherLastName';
      }
    } else if (otherUsername != null && otherUsername.isNotEmpty) {
      displayName = otherUsername;
    } else {
      displayName = 'Unknown User';
    }

    final String initials = _getInitials(
      otherFirstName,
      otherLastName,
      otherUsername,
    );
    final String timestamp = _formatTimestamp(lastMessageTime);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.blue.shade100,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          if (timestamp.isNotEmpty)
            Text(
              timestamp,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
        ],
      ),
      subtitle:
          lastMessageContent != null
              ? Text(
                lastMessageContent,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
              : null,
      onTap: () {
        if (otherUserId != null && conversationId != null) {
          // Close search
          _closeSearch();

          // Navigate to DM thread screen
          slidePush(
            context,
            DMThreadScreen(
              currentUserId: widget.userId,
              otherUserId: otherUserId,
              otherUserName: displayName,
              conversationId: conversationId,
            ),
          );
        }
      },
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final firstName = member['firstName'] as String? ?? '';
    final lastName = member['lastName'] as String? ?? '';
    final username = member['username'] as String? ?? '';

    String displayName = '';
    if (firstName.isNotEmpty) {
      displayName = firstName;
      if (lastName.isNotEmpty) {
        displayName += ' $lastName';
      }
    } else if (username.isNotEmpty) {
      displayName = username;
    } else {
      displayName = 'Unknown User';
    }

    final String initials = _getInitials(firstName, lastName, username);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.blue.shade100,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle:
          username.isNotEmpty && username != displayName
              ? Text(
                '@$username',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              )
              : null,
      onTap: () => _startConversationWith(member),
    );
  }
}
