import 'package:flutter/material.dart';
import '../widgets/user_avatar.dart';

class AvatarUtils {
  /// Build an avatar for any conversation (1:1 or group)
  /// Works for messages home screen, DM thread app bar, and all avatar needs
  static Widget buildGroupAvatar({
    required List<Map<String, dynamic>>? participants,
    required bool hasUnread,
    required double radius,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    // Fallback for empty or missing participants
    if (participants == null || participants.isEmpty) {
      return GestureDetector(
        onTap: onTap,
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Colors.deepPurple.shade400,
          child: Icon(Icons.group, color: Colors.white, size: radius * 0.8),
        ),
      );
    }

    // Single participant - use UserAvatar for consistency
    if (participants.length == 1) {
      final participant = participants.first;
      return GestureDetector(
        onTap: onTap,
        child: UserAvatar(
          photoUrl: participant['photo'] as String?,
          firstName: participant['first_name'] as String?,
          lastName: participant['last_name'] as String?,
          radius: radius,
          showBorder: true,
          borderColor:
              hasUnread ? Colors.white : Colors.white.withValues(alpha: 0.3),
          borderWidth: hasUnread ? 2.0 : 1.0,
          fontSize: fontSize,
          useFirstInitialOnly: true,
        ),
      );
    }

    // Multiple participants - create a mosaic using UserAvatar widgets
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                hasUnread ? Colors.white : Colors.white.withValues(alpha: 0.3),
            width: hasUnread ? 2.0 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            // First participant (top-left)
            if (participants.isNotEmpty)
              Positioned(
                left: radius * 0.1,
                top: radius * 0.1,
                child: Container(
                  width: radius * 0.9,
                  height: radius * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: ClipOval(
                    child: UserAvatar(
                      photoUrl: participants[0]['photo'] as String?,
                      firstName: participants[0]['first_name'] as String?,
                      lastName: participants[0]['last_name'] as String?,
                      radius: radius * 0.45,
                      fontSize: fontSize * 0.6,
                      useFirstInitialOnly: true,
                    ),
                  ),
                ),
              ),
            // Second participant (bottom-right)
            if (participants.length > 1)
              Positioned(
                right: radius * 0.1,
                bottom: radius * 0.1,
                child: Container(
                  width: radius * 0.9,
                  height: radius * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: ClipOval(
                    child: UserAvatar(
                      photoUrl: participants[1]['photo'] as String?,
                      firstName: participants[1]['first_name'] as String?,
                      lastName: participants[1]['last_name'] as String?,
                      radius: radius * 0.45,
                      fontSize: fontSize * 0.6,
                      useFirstInitialOnly: true,
                    ),
                  ),
                ),
              ),
            // Third participant (top-right)
            if (participants.length > 2)
              Positioned(
                right: radius * 0.1,
                top: radius * 0.1,
                child: Container(
                  width: radius * 0.9,
                  height: radius * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: ClipOval(
                    child: UserAvatar(
                      photoUrl: participants[2]['photo'] as String?,
                      firstName: participants[2]['first_name'] as String?,
                      lastName: participants[2]['last_name'] as String?,
                      radius: radius * 0.45,
                      fontSize: fontSize * 0.6,
                      useFirstInitialOnly: true,
                    ),
                  ),
                ),
              ),
            // Fourth participant (bottom-left)
            if (participants.length > 3)
              Positioned(
                left: radius * 0.1,
                bottom: radius * 0.1,
                child: Container(
                  width: radius * 0.9,
                  height: radius * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: ClipOval(
                    child: UserAvatar(
                      photoUrl: participants[3]['photo'] as String?,
                      firstName: participants[3]['first_name'] as String?,
                      lastName: participants[3]['last_name'] as String?,
                      radius: radius * 0.45,
                      fontSize: fontSize * 0.6,
                      useFirstInitialOnly: true,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build a 1:1 user avatar with consistent styling
  static Widget buildUserAvatar({
    required String? photoUrl,
    required String? firstName,
    required String? lastName,
    required double radius,
    required double fontSize,
    bool hasUnread = false,
    VoidCallback? onTap,
  }) {
    final avatar = UserAvatar(
      photoUrl: photoUrl,
      firstName: firstName,
      lastName: lastName,
      radius: radius,
      fontSize: fontSize,
      useFirstInitialOnly: true,
      showBorder: hasUnread,
      borderColor:
          hasUnread ? Colors.white : Colors.white.withValues(alpha: 0.3),
      borderWidth: hasUnread ? 2.0 : 1.0,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }
}
