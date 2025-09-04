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

  Color _getAvatarColor(BuildContext context) {
    if (backgroundColor != null) return backgroundColor!;

    // Generate color based on initials/name for consistency
    final name = firstName ?? displayName ?? '';
    if (name.isEmpty) {
      return Colors.grey;
    }

    // Get the base color from hash (consistent for same name)
    final baseColor = Color(name.hashCode | 0xFF000000);

    // Adjust color based on theme for better visibility
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (isDarkMode) {
      // In dark mode: lighten very dark colors, darken very light colors
      final hsl = HSLColor.fromColor(baseColor);

      // Ensure minimum lightness for visibility in dark mode
      final adjustedLightness =
          hsl.lightness < 0.3
              ? 0.6 // Lighten very dark colors
              : hsl.lightness > 0.8
              ? 0.7 // Slightly darken very light colors
              : hsl.lightness;

      // Reduce saturation slightly for softer appearance in dark mode
      final adjustedSaturation = (hsl.saturation * 0.8).clamp(0.0, 1.0);

      return hsl
          .withLightness(adjustedLightness)
          .withSaturation(adjustedSaturation)
          .toColor();
    } else {
      // In light mode: ensure colors aren't too light
      final hsl = HSLColor.fromColor(baseColor);

      // Ensure maximum lightness for visibility in light mode
      final adjustedLightness =
          hsl.lightness > 0.8
              ? 0.6 // Darken very light colors
              : hsl.lightness < 0.2
              ? 0.4 // Lighten very dark colors
              : hsl.lightness;

      return hsl.withLightness(adjustedLightness).toColor();
    }
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
    final avatarColor = _getAvatarColor(context);
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
