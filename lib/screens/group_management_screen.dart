import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../utils/page_transitions.dart';
import 'choose_dm_recipient_screen.dart';

class GroupManagementScreen extends StatefulWidget {
  final int conversationId;
  final String groupName;
  final int currentUserId;
  final List<Map<String, dynamic>> participants;
  final VoidCallback?
  onParticipantsChanged; // Add callback for participant changes

  const GroupManagementScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.currentUserId,
    required this.participants,
    this.onParticipantsChanged, // Add callback parameter
  });

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _participants = List.from(widget.participants);
    debugPrint(
      '🔧 GroupManagementScreen: Loaded ${_participants.length} participants',
    );
  }

  // Add new members to the group
  Future<void> _addMembers() async {
    try {
      final result = await slidePush(
        context,
        ChooseDMRecipientScreen(
          userId: widget.currentUserId,
          isGroupMode: true,
          existingParticipants:
              _participants.map((p) => p['id'] as int).toList(),
          isAddingToExistingGroup: true,
        ),
      );

      if (result != null && result is List<int> && result.isNotEmpty) {
        setState(() {
          _isLoading = true;
        });

        debugPrint('🔧 Adding ${result.length} new members to group');

        final apiService = Provider.of<ApiService>(context, listen: false);
        final response = await apiService.addGroupParticipants(
          widget.conversationId,
          result,
        );

        debugPrint('✅ Successfully added participants: ${response['message']}');

        // Add the new participants to local state
        final addedParticipants =
            response['addedParticipants'] as List<dynamic>?;
        if (addedParticipants != null) {
          setState(() {
            for (var participant in addedParticipants) {
              _participants.add(Map<String, dynamic>.from(participant));
            }
            _isLoading = false;
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${result.length} member(s) successfully'),
              backgroundColor: Colors.green,
            ),
          );

          // Notify parent screen about participant changes
          widget.onParticipantsChanged?.call();
        }
      }
    } catch (e) {
      debugPrint('❌ Error adding members: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding members: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Remove a member from the group
  Future<void> _removeMember(Map<String, dynamic> participant) async {
    final participantName =
        participant['first_name'] ?? participant['username'] ?? 'Unknown';

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remove Member'),
            content: Text(
              'Are you sure you want to remove $participantName from the group?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        setState(() {
          _isLoading = true;
        });

        debugPrint('🔧 Removing member: $participantName');

        final apiService = Provider.of<ApiService>(context, listen: false);
        final response = await apiService.removeGroupParticipant(
          widget.conversationId,
          participant['id'] as int,
        );

        debugPrint(
          '✅ Successfully removed participant: ${response['message']}',
        );

        // Remove from local state immediately
        setState(() {
          _participants.removeWhere((p) => p['id'] == participant['id']);
          _isLoading = false;
        });

        // Notify parent screen about participant changes
        widget.onParticipantsChanged?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$participantName removed successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // If the group is now empty or user removed themselves, go back
        final remainingMembers = response['remainingMembers'] as int? ?? 0;
        if (remainingMembers <= 1 ||
            participant['id'] == widget.currentUserId) {
          if (mounted) {
            Navigator.pop(context);
          }
        }
      } catch (e) {
        debugPrint('❌ Error removing member: $e');
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing member: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Leave the group
  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Group'),
            content: const Text(
              'Are you sure you want to leave this group? You won\'t be able to see new messages.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Leave'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        setState(() {
          _isLoading = true;
        });

        debugPrint('🔧 User leaving group');

        final apiService = Provider.of<ApiService>(context, listen: false);
        await apiService.removeGroupParticipant(
          widget.conversationId,
          widget.currentUserId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have left the group'),
              backgroundColor: Colors.green,
            ),
          );

          // Notify parent screen about participant changes
          widget.onParticipantsChanged?.call();

          Navigator.pop(context);
        }
      } catch (e) {
        debugPrint('❌ Error leaving group: $e');
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error leaving group: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildParticipantTile(Map<String, dynamic> participant) {
    // Handle both naming conventions for participant data
    final firstName =
        participant['first_name'] as String? ??
        participant['firstName'] as String? ??
        '';
    final lastName =
        participant['last_name'] as String? ??
        participant['lastName'] as String? ??
        '';
    final username = participant['username'] as String? ?? 'Unknown';
    final photo = participant['photo'] as String?;
    final userId = participant['id'] as int? ?? 0;

    final displayName =
        firstName.isNotEmpty && lastName.isNotEmpty
            ? '$firstName $lastName'
            : username;

    final isCurrentUser = userId == widget.currentUserId;
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Construct full URL for photo since backend returns relative paths
    final String? fullPhotoUrl =
        photo != null && photo.isNotEmpty
            ? (photo.startsWith('http')
                ? photo
                : '${apiService.mediaBaseUrl}$photo')
            : null;

    // Debug print to help diagnose avatar issues
    if (photo != null && photo.isNotEmpty) {
      debugPrint(
        '👤 GroupManagement: User $displayName has photo: $photo -> $fullPhotoUrl',
      );
    } else {
      debugPrint(
        '👤 GroupManagement: User $displayName has no photo, using initials',
      );
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.deepPurple.shade400,
        child:
            fullPhotoUrl != null
                ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: fullPhotoUrl,
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    placeholder:
                        (context, url) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(
                            Icons.person,
                            size: 20,
                            color: Colors.grey,
                          ),
                        ),
                    errorWidget: (context, url, error) {
                      debugPrint(
                        '❌ GroupManagement: Failed to load avatar for $displayName: $error',
                      );
                      return Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                )
                : Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
          color: Colors.white,
        ),
      ),
      subtitle:
          isCurrentUser
              ? const Text('You', style: TextStyle(color: Colors.white70))
              : null,
      trailing:
          !isCurrentUser
              ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'remove') {
                    _removeMember(participant);
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.person_remove, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Remove from group'),
                          ],
                        ),
                      ),
                    ],
              )
              : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${_participants.length} members',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: _addMembers,
            tooltip: 'Add members',
          ),
        ],
      ),
      body: GradientBackground(
        child: Column(
          children: [
            // Members list
            Expanded(
              child: ListView.builder(
                itemCount: _participants.length,
                itemBuilder: (context, index) {
                  return _buildParticipantTile(_participants[index]);
                },
              ),
            ),

            // Leave group button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _leaveGroup,
                icon: const Icon(Icons.exit_to_app, color: Colors.white),
                label: const Text(
                  'Leave Group',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
