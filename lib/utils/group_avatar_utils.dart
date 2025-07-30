import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class GroupAvatarUtils {
  // Avatar colors - same as MessagesHomeScreen
  static const List<Color> _avatarColors = [
    Color(0xFFFFC107), // A - Amber/Yellow
    Color(0xFF2196F3), // B - Blue
    Color(0xFF00BCD4), // C - Cyan
    Color(0xFF673AB7), // D - Deep Purple
    Color(0xFF4CAF50), // E - Green
    Color(0xFF3F51B5), // F - Indigo
    Color(0xFFFF9800), // G - Orange
    Color(0xFFE91E63), // H - Pink
    Color(0xFFF44336), // I - Red
    Color(0xFF009688), // J - Teal
  ];

  static Color getAvatarColor(String name) {
    if (name.isEmpty) return Colors.grey.shade600;
    final firstLetter = name.toUpperCase()[0];
    if (firstLetter.codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
        firstLetter.codeUnitAt(0) <= 'Z'.codeUnitAt(0)) {
      final index = firstLetter.codeUnitAt(0) - 'A'.codeUnitAt(0);
      return _avatarColors[index % _avatarColors.length];
    }
    return Colors.grey.shade600;
  }

  static Color getTextColor(Color backgroundColor) {
    // Use black text for yellow/amber backgrounds, white for others
    return backgroundColor.value == 0xFFFFC107 ? Colors.black : Colors.white;
  }

  static String getInitials(
    String? firstName,
    String? lastName,
    String? username,
  ) {
    if (firstName != null && firstName.isNotEmpty) {
      if (lastName != null && lastName.isNotEmpty) {
        return '${firstName[0]}${lastName[0]}'.toUpperCase();
      }
      return firstName[0].toUpperCase();
    }
    if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }

  /// Build group avatar exactly like MessagesHomeScreen
  static Widget buildGroupAvatar(
    List<Map<String, dynamic>>? participants,
    ApiService apiService, {
    VoidCallback? onTap,
  }) {
    Widget avatarWidget;

    if (participants != null && participants.isNotEmpty) {
      // Special case for single participant - center it
      if (participants.length == 1) {
        avatarWidget = SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: ClipOval(
                child: buildParticipantAvatar(
                  participants[0],
                  apiService,
                  isSmall: false, // Use full size for single avatar
                ),
              ),
            ),
          ),
        );
      } else {
        // Google Messages style: max 4 avatars in corners for multiple participants
        avatarWidget = SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            children: [
              // First participant (top-left)
              if (participants.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: buildParticipantAvatar(
                        participants[0],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
              // Second participant (bottom-right)
              if (participants.length > 1)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: buildParticipantAvatar(
                        participants[1],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
              // Third participant (top-right)
              if (participants.length > 2)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: buildParticipantAvatar(
                        participants[2],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
              // Fourth participant (bottom-left)
              if (participants.length > 3)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: ClipOval(
                      child: buildParticipantAvatar(
                        participants[3],
                        apiService,
                        isSmall: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    } else {
      // Fallback to simple group avatar
      avatarWidget = CircleAvatar(
        radius: 24,
        backgroundColor: Colors.deepPurple.shade400,
        child: const Icon(Icons.group, color: Colors.white, size: 24),
      );
    }

    // Wrap with gesture detector if onTap provided
    Widget result = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
      ),
      child: avatarWidget,
    );

    if (onTap != null) {
      result = GestureDetector(onTap: onTap, child: result);
    }

    return result;
  }

  /// Build individual participant avatar
  static Widget buildParticipantAvatar(
    Map<String, dynamic> participant,
    ApiService apiService, {
    bool isSmall = false,
  }) {
    final photoUrl = participant['photo'] as String?;
    final firstName =
        participant['first_name'] as String? ??
        participant['firstName'] as String? ??
        '';
    final lastName =
        participant['last_name'] as String? ??
        participant['lastName'] as String? ??
        '';
    final username = participant['username'] as String? ?? '';

    final initials = getInitials(firstName, lastName, username);
    final size = isSmall ? 12.0 : 20.0;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      final fullUrl =
          photoUrl.startsWith('http')
              ? photoUrl
              : '${apiService.mediaBaseUrl}$photoUrl';

      return CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => Container(
              color: Colors.grey.shade300,
              child: Icon(Icons.person, size: size, color: Colors.grey),
            ),
        errorWidget: (context, url, error) {
          final avatarColor = getAvatarColor(initials);
          return CircleAvatar(
            backgroundColor: avatarColor,
            child: Text(
              initials,
              style: TextStyle(
                color: getTextColor(avatarColor),
                fontWeight: FontWeight.bold,
                fontSize: isSmall ? 8 : 12,
              ),
            ),
          );
        },
      );
    }

    // No photo, show initials
    final avatarColor = getAvatarColor(initials);
    return CircleAvatar(
      backgroundColor: avatarColor,
      child: Text(
        initials,
        style: TextStyle(
          color: getTextColor(avatarColor),
          fontWeight: FontWeight.bold,
          fontSize: isSmall ? 8 : 12,
        ),
      ),
    );
  }
}
