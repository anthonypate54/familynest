import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

import '../widgets/gradient_background.dart';
import '../widgets/user_avatar.dart';
import '../utils/page_transitions.dart';
import 'dm_thread_screen.dart';
import 'group_name_screen.dart';
import '../theme/app_theme.dart';

class ChooseDMRecipientScreen extends StatefulWidget {
  final int userId;
  final bool isGroupMode;
  final List<int> existingParticipants;
  final bool isAddingToExistingGroup;

  const ChooseDMRecipientScreen({
    super.key,
    required this.userId,
    this.isGroupMode = false,
    this.existingParticipants = const [],
    this.isAddingToExistingGroup = false,
  });

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

  // Group chat state
  bool _isGroupMode = false;
  Set<Map<String, dynamic>> _selectedMembers = {};

  @override
  void initState() {
    super.initState();
    _isGroupMode = widget.isGroupMode;
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
      // Use the new method that gets members from ALL families
      final members = await apiService.getAllFamilyMembers();

      // Filter out existing participants if in group mode
      final filteredMembers =
          members.where((member) {
            final isExistingParticipant = widget.existingParticipants.contains(
              member['userId'],
            );
            return !isExistingParticipant;
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

          // Navigate to DM thread and clear navigation stack
          // This ensures that pressing back goes to the conversation list, not the recipient selection
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder:
                  (context) => DMThreadScreen(
                    currentUserId: widget.userId,
                    otherUserId: memberId,
                    otherUserName: displayName,
                    otherUserPhoto: member['photo'] as String?,
                    conversationId: conversationId,
                  ),
            ),
            (route) =>
                route
                    .isFirst, // Remove all routes except the first (root) route
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
      _searchController.clear(); // Clear the search text
      _filteredMembers.clear();
      _familyMembers.clear();
    });
    // Reload the family members to restore the list
    _loadFamilyMembers();
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

  // Helper method to build selected members chips
  Widget _buildSelectedMembersChips() {
    if (_selectedMembers.isEmpty) {
      return TextField(
        controller: _searchController,
        onChanged: _filterMembers,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.white,
        decoration: const InputDecoration(
          hintText: 'Add participants...',
          hintStyle: TextStyle(color: Colors.white70),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
          filled: false,
          fillColor: Colors.transparent,
        ),
      );
    }

    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._selectedMembers.map((member) {
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

          return Chip(
            label: Text(
              displayName,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
            backgroundColor: Colors.white.withOpacity(0.9),
            deleteIcon: const Icon(
              Icons.close,
              color: Colors.black54,
              size: 18,
            ),
            onDeleted: () {
              setState(() {
                _selectedMembers.remove(member);
              });
            },
          );
        }).toList(),

        // Add more participants field
        if (_selectedMembers.length < 4) // Max 4 others + creator = 5 total
          SizedBox(
            width: 100,
            height: 32, // Match chip height
            child: Center(
              child: TextField(
                controller: _searchController,
                onChanged: _filterMembers,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Add more...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Helper method to build search field for normal mode
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _filterMembers,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      decoration: const InputDecoration(
        hintText: 'Type name, phone number, or email',
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
        filled: false,
        fillColor: Colors.transparent,
      ),
    );
  }

  // Helper method to build create group button
  Widget _buildCreateGroupButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _toggleGroupMode,
        icon: const Icon(Icons.group_add, color: Colors.white),
        label: const Text(
          'Create group',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.2),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // Helper method to build next button for group mode
  Widget _buildNextButton() {
    final isAddingToGroup = widget.isAddingToExistingGroup;
    final buttonText =
        isAddingToGroup
            ? 'Add (${_selectedMembers.length})'
            : 'Next (${_selectedMembers.length})';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton(
          onPressed:
              isAddingToGroup ? _addSelectedParticipants : _proceedToGroupName,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            buttonText,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    );
  }

  // Add selected participants to existing group (return user IDs)
  void _addSelectedParticipants() {
    final selectedUserIds =
        _selectedMembers.map((member) => member['userId'] as int).toList();
    Navigator.pop(context, selectedUserIds);
  }

  // Proceed to group name screen
  void _proceedToGroupName() {
    slidePush(
      context,
      GroupNameScreen(
        currentUserId: widget.userId,
        selectedMembers: _selectedMembers.toList(),
      ),
    );
  }

  // Toggle between normal and group mode
  void _toggleGroupMode() {
    setState(() {
      _isGroupMode = !_isGroupMode;
      _selectedMembers.clear();
      _searchController.clear();
      _filteredMembers = _familyMembers;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.isAddingToExistingGroup
                    ? 'Add participants'
                    : (_isGroupMode ? 'New group chat' : 'New chat'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // User avatar
            UserAvatar(
              displayName: 'U',
              radius: 18,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.2),
            ),
            const SizedBox(width: 8),
          ],
        ),
        elevation: 0,
      ),
      body: GradientBackground(
        child: Column(
          children: [
            // "To:" field with selected members and Create group button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // To: field row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // "To:" label
                      Text(
                        'To:',
                        style: TextStyle(
                          color:
                              Colors
                                  .white, // White text on green gradient background
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Selected members or search field
                      Expanded(
                        child:
                            _isGroupMode
                                ? _buildSelectedMembersChips()
                                : _buildSearchField(),
                      ),
                    ],
                  ),

                  // Create group button (only in normal mode)
                  if (!_isGroupMode) ...[
                    const SizedBox(height: 12),
                    _buildCreateGroupButton(),
                  ],

                  // Next button (only in group mode with selections)
                  if (_isGroupMode && _selectedMembers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildNextButton(),
                  ],
                ],
              ),
            ),

            // Family members list with gradient background
            Expanded(
              child: Container(
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
                                'Error loading contacts',
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
                                onPressed: _loadFamilyMembers,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                        : _familyMembers.isEmpty
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.family_restroom,
                                size: 64,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No family contacts found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Join or create a family to start messaging',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
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
    final bool isSelected = _selectedMembers.contains(member);
    final bool isAtLimit =
        _selectedMembers.length >= 4; // Max 4 others + creator = 5 total

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color:
            _isGroupMode && isSelected
                ? Colors.white.withOpacity(
                  0.3,
                ) // Highlight selected in group mode
                : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading:
            _isGroupMode
                ? _buildGroupModeLeading(isSelected, isAtLimit, member)
                : _buildNormalModeLeading(initials, member),
        title: Text(
          displayName,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        subtitle:
            username.isNotEmpty && username != displayName
                ? Text(
                  '@$username',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                )
                : null,
        onTap:
            () =>
                _isGroupMode
                    ? _toggleMemberSelection(member)
                    : _startConversationWith(member),
      ),
    );
  }

  // Helper method to build leading widget for normal mode (avatar only)
  Widget _buildNormalModeLeading(String initials, Map<String, dynamic> member) {
    final firstName = member['firstName'] as String? ?? '';
    final lastName = member['lastName'] as String? ?? '';
    final photo = member['photo'] as String?;

    return UserAvatar(
      photoUrl: photo,
      firstName: firstName,
      lastName: lastName,
      displayName: initials,
      radius: 24,
      fontSize: 18,
      useFirstInitialOnly: true,
    );
  }

  // Helper method to build leading widget for group mode (checkbox + avatar)
  Widget _buildGroupModeLeading(
    bool isSelected,
    bool isAtLimit,
    Map<String, dynamic> member,
  ) {
    final firstName = member['firstName'] as String? ?? '';
    final lastName = member['lastName'] as String? ?? '';
    final username = member['username'] as String? ?? '';
    final photo = member['photo'] as String?;
    final String initials = _getInitials(firstName, lastName, username);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Checkbox
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.transparent,
            border: Border.all(
              color:
                  isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.white.withOpacity(0.5),
              width: 2,
            ),
          ),
          child:
              isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
        ),
        const SizedBox(width: 12),
        // Avatar with photo support
        UserAvatar(
          photoUrl: photo,
          firstName: firstName,
          lastName: lastName,
          displayName: initials,
          radius: 20,
          fontSize: 16,
          useFirstInitialOnly: true,
        ),
      ],
    );
  }

  // Toggle member selection in group mode
  void _toggleMemberSelection(Map<String, dynamic> member) {
    setState(() {
      if (_selectedMembers.contains(member)) {
        _selectedMembers.remove(member);
      } else {
        // Check limit (max 4 others + creator = 5 total)
        if (_selectedMembers.length < 4) {
          _selectedMembers.add(member);
          _searchController.clear(); // Clear search text after adding
        } else {
          // Show limit message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 5 people allowed in a group chat'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }
}
