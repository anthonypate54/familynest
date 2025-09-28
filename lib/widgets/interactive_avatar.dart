import 'package:flutter/material.dart';
import 'user_avatar.dart';

/// An interactive avatar that shows user details when pressed
class InteractiveAvatar extends StatefulWidget {
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

  const InteractiveAvatar({
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

  @override
  State<InteractiveAvatar> createState() => _InteractiveAvatarState();
}

class _InteractiveAvatarState extends State<InteractiveAvatar> {
  final GlobalKey _avatarKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showTooltip() {
    // Get the position of the avatar in the screen
    final RenderBox renderBox =
        _avatarKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Create the overlay entry
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: position.dx,
          top: position.dy + size.height + 5, // Position below the avatar
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            color:
                Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Full name
                  if ((widget.firstName?.isNotEmpty ?? false) ||
                      (widget.lastName?.isNotEmpty ?? false))
                    Text(
                      '${widget.firstName ?? ''} ${widget.lastName ?? ''}'
                          .trim(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                      ),
                    ),

                  // Username
                  if (widget.displayName?.isNotEmpty ?? false)
                    Text(
                      '@${widget.displayName}',
                      style: TextStyle(
                        color:
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[400]
                                : Colors.grey[700],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Add the overlay to the screen
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _avatarKey,
      onTapDown: (_) {
        _showTooltip();
      },
      onTapUp: (_) {
        _removeOverlay();
      },
      onTapCancel: () {
        _removeOverlay();
      },
      child: UserAvatar(
        photoUrl: widget.photoUrl,
        firstName: widget.firstName,
        lastName: widget.lastName,
        displayName: widget.displayName,
        radius: widget.radius,
        backgroundColor: widget.backgroundColor,
        borderColor: widget.borderColor,
        borderWidth: widget.borderWidth,
        showBorder: widget.showBorder,
        fontSize: widget.fontSize,
        useFirstInitialOnly: widget.useFirstInitialOnly,
      ),
    );
  }
}
