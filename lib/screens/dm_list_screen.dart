import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/gradient_background.dart';
import 'dm_thread_screen.dart';
import '../utils/page_transitions.dart';
import '../models/dm_conversation.dart';
import '../theme/app_theme.dart';

class ChooseDMRecipientScreen extends StatefulWidget {
  final int userId;

  const ChooseDMRecipientScreen({super.key, required this.userId});

  @override
  State<ChooseDMRecipientScreen> createState() =>
      _ChooseDMRecipientScreenState();
}

class _ChooseDMRecipientScreenState extends State<ChooseDMRecipientScreen> {
  List<Map<String, dynamic>> _familyMembers = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredMembers = [];
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyMembers() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final apiService = Provider.of<ApiService>(context, listen: false);
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

  void _filterMembers(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredMembers = _familyMembers;
      });
      return;
    }

    final lowercaseQuery = query.toLowerCase();

    // Filter family members
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
      final conversation = await apiService.getOrCreateConversation(memberId);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (conversation != null) {
          final conversationId = conversation.id;
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
              otherUserPhoto: member['photo'] as String?,
              conversationId: conversationId,
            ),
          );
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
      _filteredMembers.clear();
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
        backgroundColor: AppTheme.getAppBarColor(context),
        title: const Text('Choose Person to Message'),
        elevation: 0,
      ),
      body: GradientBackground(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _filterMembers,
                decoration: InputDecoration(
                  hintText: 'Search family members...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.9),
                ),
              ),
            ),

            // Family members list
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                      ? Center(child: Text(_errorMessage!))
                      : ListView.builder(
                        itemCount:
                            _searchController.text.isEmpty
                                ? _familyMembers.length
                                : _filteredMembers.length,
                        itemBuilder: (context, index) {
                          final member =
                              _searchController.text.isEmpty
                                  ? _familyMembers[index]
                                  : _filteredMembers[index];
                          return _buildMemberTile(member);
                        },
                      ),
            ),
          ],
        ),
      ),
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
