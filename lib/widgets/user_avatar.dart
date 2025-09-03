import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final double radius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final bool showBorder;
  final double? fontSize;
  final bool useFirstInitialOnly;

  const UserAvatar({
    super.key,
    this.photoUrl,
    this.firstName,
    this.lastName,
    this.displayName,
    this.radius = 20,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.showBorder = false,
    this.fontSize,
    this.useFirstInitialOnly = false,
  });

  String _getInitials() {
    // If useFirstInitialOnly is true, just return first initial
    if (useFirstInitialOnly) {
      if (firstName != null && firstName!.isNotEmpty) {
        return firstName![0].toUpperCase();
      }
      if (displayName != null && displayName!.isNotEmpty) {
        return displayName![0].toUpperCase();
      }
      return '?';
    }

    // Try firstName + lastName first
    if (firstName != null && firstName!.isNotEmpty) {
      if (lastName != null && lastName!.isNotEmpty) {
        return '${firstName![0]}${lastName![0]}'.toUpperCase();
      }
      return firstName![0].toUpperCase();
    }

    // Fall back to displayName
    if (displayName != null && displayName!.isNotEmpty) {
      final words =
          displayName!.split(' ').where((word) => word.isNotEmpty).toList();
      if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
        return '${words[0][0]}${words[1][0]}'.toUpperCase();
      }
      if (words.isNotEmpty && words[0].isNotEmpty) {
        return words[0][0].toUpperCase();
      }
    }

    return '?';
  }

  Color _getAvatarColor() {
    if (backgroundColor != null) return backgroundColor!;

    // Generate color based on initials/name for consistency
    final name = firstName ?? displayName ?? '';
    if (name.isNotEmpty) {
      return Color(name.hashCode | 0xFF000000);
    }
    return Colors.grey;
  }

  Color _getTextColor(Color backgroundColor) {
    // Calculate brightness to determine text color
    final brightness = backgroundColor.computeLuminance();
    return brightness > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final initials = _getInitials();
    final avatarColor = _getAvatarColor();
    final textColor = _getTextColor(avatarColor);

    // Construct full URL for photo since backend returns relative paths
    final String? fullPhotoUrl =
        photoUrl != null && photoUrl!.isNotEmpty
            ? (photoUrl!.startsWith('http')
                ? photoUrl
                : '${apiService.mediaBaseUrl}$photoUrl')
            : null;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: avatarColor,
      child:
          fullPhotoUrl != null
              ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: fullPhotoUrl,
                  fit: BoxFit.cover,
                  width: radius * 2,
                  height: radius * 2,
                  placeholder:
                      (context, url) => Container(
                        color: Colors.grey.shade300,
                        child: Icon(
                          Icons.person,
                          size: radius * 0.6,
                          color: Colors.grey,
                        ),
                      ),
                  errorWidget: (context, url, error) {
                    return Text(
                      initials,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize ?? (radius * 0.6),
                      ),
                    );
                  },
                ),
              )
              : Text(
                initials,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize ?? (radius * 0.6),
                ),
              ),
    );

    if (showBorder) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor ?? Colors.white,
            width: borderWidth,
          ),
        ),
        child: avatar,
      );
    }

    return avatar;
  }
}
