import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/gradient_background.dart';
import '../widgets/user_avatar.dart';
import 'dm_thread_screen.dart';
import '../theme/app_theme.dart';

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
          // Navigate to the group thread
          Navigator.of(context).pushReplacement(
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

    return SizedBox(
      height: avatarSize,
      width: (widget.selectedMembers.length * overlap) + avatarSize - overlap,
      child: Stack(
        children:
            widget.selectedMembers.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;

              final firstName = member['firstName'] as String? ?? '';
              final lastName = member['lastName'] as String? ?? '';
              final username = member['username'] as String? ?? '';

              return Positioned(
                left: index * overlap,
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: UserAvatar(
                    firstName: firstName,
                    lastName: lastName,
                    displayName: username,
                    radius: (avatarSize - 4) / 2,
                    fontSize: 12,
                    useFirstInitialOnly: true,
                  ),
                ),
              );
            }).toList(),
      ),
    );
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
                style: TextStyle(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                  fontSize: 18,
                ),
                cursorColor:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                decoration: InputDecoration(
                  labelText: 'Group name (optional)',
                  labelStyle: TextStyle(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withOpacity(0.7)
                            : Colors.black.withOpacity(0.6),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.black.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                      width: 2,
                    ),
                  ),
                  suffixIcon:
                      _groupNameController.text.isNotEmpty
                          ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black54,
                            ),
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
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.7)
                          : Colors.black.withOpacity(0.6),
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
