import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/family.dart';
import '../services/api_service.dart';
import 'package:provider/provider.dart';

class FamilyCard extends StatefulWidget {
  final Family family;
  final int currentUserId;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onInvite;
  final VoidCallback? onLeave;
  final VoidCallback? onMute;
  final VoidCallback? onViewMembers;
  final VoidCallback? onNotificationSettings;

  const FamilyCard({
    Key? key,
    required this.family,
    required this.currentUserId,
    this.onTap,
    this.onEdit,
    this.onInvite,
    this.onLeave,
    this.onMute,
    this.onViewMembers,
    this.onNotificationSettings,
  }) : super(key: key);

  @override
  State<FamilyCard> createState() => _FamilyCardState();
}

class _FamilyCardState extends State<FamilyCard> {
  @override
  Widget build(BuildContext context) {
    final family = widget.family;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with gradient background
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    family.roleColor.withValues(alpha: 0.8),
                    family.roleColor.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  // Family icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(family.roleIcon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Family name and details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          family.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                family.roleDisplayText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${family.memberCount} members',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status indicators
                  Column(
                    children: [
                      if (family.isMuted)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.volume_off,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      if (!family.receiveMessages)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.notifications_off,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Content section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        icon: Icons.people,
                        label: 'Active',
                        value: '${family.activeMembers.length}',
                        color: Colors.green,
                      ),
                      _buildStatItem(
                        icon: Icons.admin_panel_settings,
                        label: 'Admins',
                        value: '${family.admins.length}',
                        color: Colors.orange,
                      ),
                      _buildStatItem(
                        icon: Icons.volume_off,
                        label: 'Muted',
                        value: '${family.mutedMembers.length}',
                        color: Colors.red,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    children: [
                      // View members button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onViewMembers,
                          icon: const Icon(Icons.people, size: 18),
                          label: const Text('Members'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Notification settings button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onNotificationSettings,
                          icon: Icon(
                            family.isMuted
                                ? Icons.volume_off
                                : Icons.notifications,
                            size: 18,
                          ),
                          label: const Text('Settings'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                family.isMuted ? Colors.red : Colors.grey[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Owner controls
                  if (family.isOwned) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onInvite,
                            icon: const Icon(Icons.person_add, size: 18),
                            label: const Text('Invite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Member controls
                  if (family.canLeave) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onLeave,
                        icon: const Icon(Icons.exit_to_app, size: 18),
                        label: const Text('Leave Family'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
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

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class FamilyMemberCard extends StatefulWidget {
  final FamilyMember member;
  final int currentUserId;
  final bool canManage;
  final VoidCallback? onTap;
  final VoidCallback? onMute;
  final VoidCallback? onUnmute;
  final VoidCallback? onMessage;

  const FamilyMemberCard({
    Key? key,
    required this.member,
    required this.currentUserId,
    this.canManage = false,
    this.onTap,
    this.onMute,
    this.onUnmute,
    this.onMessage,
  }) : super(key: key);

  @override
  State<FamilyMemberCard> createState() => _FamilyMemberCardState();
}

class _FamilyMemberCardState extends State<FamilyMemberCard> {
  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final isCurrentUser = member.id == widget.currentUserId;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: widget.onTap,
        leading: _buildAvatar(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: member.isMuted ? Colors.grey : null,
                ),
              ),
            ),
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: member.roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                member.roleDisplayText,
                style: TextStyle(
                  color: member.roleColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (member.ownedFamilyName != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Owns ${member.ownedFamilyName}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mute status indicator
            if (member.isMuted)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.volume_off,
                  color: Colors.red,
                  size: 16,
                ),
              ),

            // Message button
            if (!isCurrentUser)
              IconButton(
                onPressed: widget.onMessage,
                icon: const Icon(Icons.message, size: 20),
                tooltip: 'Message ${member.displayName}',
              ),

            // Mute/unmute button
            if (widget.canManage && !isCurrentUser)
              IconButton(
                onPressed: member.isMuted ? widget.onUnmute : widget.onMute,
                icon: Icon(
                  member.isMuted ? Icons.volume_up : Icons.volume_off,
                  size: 20,
                ),
                tooltip: member.isMuted ? 'Unmute' : 'Mute',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final member = widget.member;

    return CircleAvatar(
      radius: 20,
      backgroundColor: Color(member.displayName.hashCode | 0xFF000000),
      child:
          member.photo != null && member.photo!.isNotEmpty
              ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl:
                      member.photo!.startsWith('http')
                          ? member.photo!
                          : Provider.of<ApiService>(
                                context,
                                listen: false,
                              ).mediaBaseUrl +
                              member.photo!,
                  fit: BoxFit.cover,
                  width: 40,
                  height: 40,
                  placeholder:
                      (context, url) => const CircularProgressIndicator(),
                  errorWidget:
                      (context, url, error) => Text(
                        member.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                ),
              )
              : Text(
                member.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
    );
  }
}
