import 'package:flutter/material.dart';
import '../services/video_composition_service.dart';

/// Unified send button that handles all loading states consistently across screens
/// Replaces duplicated send button logic in message_screen, dm_thread_screen, and thread_screen
class UnifiedSendButton extends StatefulWidget {
  final VideoCompositionService compositionService;
  final TextEditingController messageController;
  final bool isSending;
  final VoidCallback onSend;
  final bool
  requiresMediaOrText; // Some screens require media, others just text

  const UnifiedSendButton({
    Key? key,
    required this.compositionService,
    required this.messageController,
    required this.isSending,
    required this.onSend,
    this.requiresMediaOrText = true, // Default: require either text or media
  }) : super(key: key);

  @override
  State<UnifiedSendButton> createState() => _UnifiedSendButtonState();
}

class _UnifiedSendButtonState extends State<UnifiedSendButton> {
  Color? _primaryColor;
  bool? _isDarkMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache theme values safely to avoid unsafe lookups during state changes
    final theme = Theme.of(context);
    _primaryColor = theme.colorScheme.primary;
    _isDarkMode = theme.brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.compositionService,
        widget.messageController,
      ]),
      builder: (context, child) {
        final hasText = widget.messageController.text.trim().isNotEmpty;
        final hasMedia = widget.compositionService.hasMedia;
        final isProcessing = widget.compositionService.isProcessingMedia;

        // Determine if send button should be enabled
        final isEnabled =
            !widget.isSending &&
            !isProcessing &&
            (widget.requiresMediaOrText ? (hasText || hasMedia) : hasText);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isEnabled ? widget.onSend : null,
            borderRadius: BorderRadius.circular(
              20,
            ), // Match CircleAvatar radius
            child: CircleAvatar(
              backgroundColor: _getBackgroundColor(
                isEnabled,
                isProcessing,
                widget.isSending,
                _primaryColor!,
                _isDarkMode!,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Progress indicator for processing or sending
                  if (isProcessing || widget.isSending)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        value: null, // Indeterminate spinner
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),

                  // Send icon with different states
                  Icon(
                    _getIcon(isProcessing, widget.isSending),
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getBackgroundColor(
    bool isEnabled,
    bool isProcessing,
    bool isSending,
    Color primaryColor,
    bool isDarkMode,
  ) {
    if (isEnabled || isProcessing || isSending) {
      return primaryColor;
    }

    // Theme-aware disabled color with better contrast
    return isDarkMode
        ? Colors
            .grey
            .shade700 // Darker grey for dark mode
        : Colors.grey.shade400; // Lighter grey for light mode
  }

  IconData _getIcon(bool isProcessing, bool isSending) {
    if (isProcessing) {
      return Icons.upload; // Media is being processed
    } else if (isSending) {
      return Icons.hourglass_empty; // Message is being sent
    } else {
      return Icons.send; // Ready to send
    }
  }
}
