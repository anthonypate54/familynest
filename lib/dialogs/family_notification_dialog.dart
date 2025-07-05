import 'package:flutter/material.dart';
import '../models/family.dart';
import '../services/family_service.dart';
import '../widgets/family_card.dart';
import 'package:provider/provider.dart';

class FamilyNotificationDialog extends StatefulWidget {
  final Family family;
  final int currentUserId;

  const FamilyNotificationDialog({
    Key? key,
    required this.family,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<FamilyNotificationDialog> createState() =>
      _FamilyNotificationDialogState();
}

class _FamilyNotificationDialogState extends State<FamilyNotificationDialog> {
  late FamilyNotificationPreferences _preferences;
  late Family _family;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final familyService = FamilyService.of(context);
      final preferences = await familyService.getFamilyNotificationPreferences(
        widget.currentUserId,
        widget.family.id,
      );

      if (mounted) {
        setState(() {
          _preferences = preferences;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading notification preferences: $e');
      if (mounted) {
        setState(() {
          _preferences = FamilyNotificationPreferences();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _isSaving = true);

    try {
      final familyService = FamilyService.of(context);
      final success = await familyService.updateFamilyNotificationPreferences(
        widget.currentUserId,
        widget.family.id,
        _preferences,
      );

      if (success && mounted) {
        Navigator.of(
          context,
        ).pop(true); // Return true to indicate changes were made
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification preferences updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update notification preferences'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving notification preferences: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(_family.roleIcon, color: _family.roleColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_family.name} Settings',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: _isLoading ? _buildLoadingContent() : _buildContent(),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _savePreferences,
          child:
              _isSaving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildLoadingContent() {
    return const SizedBox(
      height: 200,
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Family-wide settings
          _buildSectionHeader('Family Settings'),
          _buildToggleOption(
            title: 'Receive Messages',
            subtitle: 'Get notified for new messages in this family',
            value: _preferences.receiveMessages,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(receiveMessages: value);
              });
            },
          ),
          _buildToggleOption(
            title: 'Receive Invitations',
            subtitle: 'Get notified when someone joins this family',
            value: _preferences.receiveInvitations,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(receiveInvitations: value);
              });
            },
          ),
          _buildToggleOption(
            title: 'Receive Reactions',
            subtitle: 'Get notified for likes and loves on messages',
            value: _preferences.receiveReactions,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(receiveReactions: value);
              });
            },
          ),
          _buildToggleOption(
            title: 'Receive Comments',
            subtitle: 'Get notified for comments on messages',
            value: _preferences.receiveComments,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(receiveComments: value);
              });
            },
          ),

          const SizedBox(height: 24),

          // Quick actions
          _buildSectionHeader('Quick Actions'),
          _buildQuickActionButton(
            title: 'Mute Family',
            subtitle:
                _preferences.muteFamily
                    ? 'Family is currently muted'
                    : 'Mute all notifications from this family',
            icon: _preferences.muteFamily ? Icons.volume_off : Icons.volume_up,
            color: _preferences.muteFamily ? Colors.red : Colors.orange,
            onTap: () {
              setState(() {
                final newMuteStatus = !_preferences.muteFamily;
                _preferences = _preferences.copyWith(
                  muteFamily: newMuteStatus,
                  receiveMessages: !newMuteStatus,
                  receiveInvitations: !newMuteStatus,
                  receiveReactions: !newMuteStatus,
                  receiveComments: !newMuteStatus,
                );
              });
            },
          ),

          const SizedBox(height: 24),

          // Member settings
          if (_family.members.isNotEmpty) ...[
            _buildSectionHeader('Individual Members'),
            Text(
              'Mute specific family members',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 8),
            ..._family.members
                .where((member) => member.id != widget.currentUserId)
                .map((member) => _buildMemberToggle(member)),
          ],

          const SizedBox(height: 24),

          // Delivery settings
          _buildSectionHeader('Delivery Settings'),
          _buildToggleOption(
            title: 'Email Notifications',
            subtitle: 'Receive notifications via email',
            value: _preferences.emailNotifications,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(emailNotifications: value);
              });
            },
          ),
          _buildToggleOption(
            title: 'Push Notifications',
            subtitle: 'Receive notifications on your device',
            value: _preferences.pushNotifications,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(pushNotifications: value);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildToggleOption({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildQuickActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.touch_app),
      ),
    );
  }

  Widget _buildMemberToggle(FamilyMember member) {
    final isMuted = _preferences.mutedMemberIds.contains(member.id);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: Color(member.displayName.hashCode | 0xFF000000),
          child:
              member.photo != null && member.photo!.isNotEmpty
                  ? ClipOval(
                    child: Image.network(
                      member.photo!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => Text(
                            member.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                    ),
                  )
                  : Text(
                    member.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
        ),
        title: Text(
          member.displayName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isMuted ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          member.roleDisplayText,
          style: TextStyle(
            fontSize: 12,
            color: isMuted ? Colors.grey : member.roleColor,
          ),
        ),
        trailing: Switch(
          value: !isMuted,
          onChanged: (value) {
            setState(() {
              List<int> newMutedIds = List.from(_preferences.mutedMemberIds);
              if (value) {
                newMutedIds.remove(member.id);
              } else {
                newMutedIds.add(member.id);
              }
              _preferences = _preferences.copyWith(mutedMemberIds: newMutedIds);
            });
          },
          activeColor: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}
