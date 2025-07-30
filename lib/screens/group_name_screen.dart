import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/gradient_background.dart';
import '../utils/page_transitions.dart';
import 'dm_thread_screen.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';

class GroupNameScreen extends StatefulWidget {
  final int currentUserId;
  final List<Map<String, dynamic>> selectedMembers;

  const GroupNameScreen({
    super.key,
    required this.currentUserId,
    required this.selectedMembers,
  });

  @override
  State<GroupNameScreen> createState() => _GroupNameScreenState();
}

class _GroupNameScreenState extends State<GroupNameScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  String _getInitials(String firstName, String lastName, String username) {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    } else if (username.isNotEmpty) {
      return username[0].toUpperCase();
    } else {
      return 'U';
    }
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Extract participant IDs
      final participantIds =
          widget.selectedMembers
              .map((member) => member['userId'] as int)
              .toList();

      // Create group chat
      final groupChat = await apiService.createGroupChat(
        groupName:
            _groupNameController.text.trim().isEmpty
                ? null
                : _groupNameController.text.trim(),
        participantIds: participantIds,
      );

      if (mounted) {
        if (groupChat != null) {
          // Navigate to the group thread and clear the navigation stack
          // This ensures that pressing back goes to the conversation list, not the group creation flow
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder:
                  (context) => DMThreadScreen(
                    currentUserId: widget.currentUserId,
                    otherUserId: 0, // Not applicable for groups
                    otherUserName: groupChat['name'] ?? 'Group Chat',
                    otherUserPhoto: null,
                    conversationId: groupChat['id'] as int,
                    isGroup: true,
                    participantCount:
                        (groupChat['participants'] as List?)?.length ??
                        widget.selectedMembers.length + 1,
                    participants:
                        groupChat['participants'] != null
                            ? List<Map<String, dynamic>>.from(
                              (groupChat['participants'] as List<dynamic>).map(
                                (item) =>
                                    Map<String, dynamic>.from(item as Map),
                              ),
                            )
                            : null,
                  ),
            ),
            (route) =>
                route
                    .isFirst, // Remove all routes except the first (root) route
          );
        } else {
          // Show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create group chat'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isCreating = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Widget _buildMemberAvatars() {
    // Build overlapping avatars like Google Messages
    const double avatarSize = 32.0;
    const double overlap = 24.0;

    // Create a combined list with creator first, then selected members
    final allMembers = <Map<String, dynamic>>[];

    // Add the creator (current user) first
    // Note: We don't have the creator's full info here, so we'll use a placeholder
    allMembers.add({
      'firstName': 'You', // Could also fetch actual user data if needed
      'lastName': '',
      'username': 'you',
    });

    // Add all selected members
    allMembers.addAll(widget.selectedMembers);

    return SizedBox(
      height: avatarSize,
      width: (allMembers.length * overlap) + avatarSize - overlap,
      child: Stack(
        children:
            allMembers.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;

              final firstName = member['firstName'] as String? ?? '';
              final lastName = member['lastName'] as String? ?? '';
              final username = member['username'] as String? ?? '';
              final initials = _getInitials(firstName, lastName, username);

              return Positioned(
                left: index * overlap,
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: (avatarSize - 4) / 2,
                    backgroundColor: _getAvatarColor(firstName),
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: _getTextColor(_getAvatarColor(firstName)),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  // Google Messages-style avatar colors (same as other screens)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add group name',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        elevation: 0,
      ),
      body: GradientBackground(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Member avatars (overlapping)
              Center(child: _buildMemberAvatars()),

              const SizedBox(height: 40),

              // Group name input
              TextField(
                controller: _groupNameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  labelText: 'Group name (optional)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 2),
                  ),
                  suffixIcon:
                      _groupNameController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _groupNameController.clear();
                              });
                            },
                          )
                          : null,
                ),
                onChanged: (value) {
                  setState(() {}); // Trigger rebuild for suffix icon
                },
              ),

              const SizedBox(height: 16),

              // Privacy note
              Text(
                'Only you can see this group name',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),

              const Spacer(),

              // Create button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child:
                      _isCreating
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
