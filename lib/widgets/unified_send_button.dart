import 'package:flutter/material.dart';
import '../services/video_composition_service.dart';

/// Unified send button that handles all loading states consistently across screens
/// Replaces duplicated send button logic in message_screen, dm_thread_screen, and thread_screen
class UnifiedSendButton extends StatelessWidget {
  final VideoCompositionService compositionService;
  final TextEditingController messageController;
  final bool isSending;
  final VoidCallback onSend;
  final bool requiresMediaOrText; // Some screens require media, others just text

  const UnifiedSendButton({
    Key? key,
    required this.compositionService,
    required this.messageController,
    required this.isSending,
    required this.onSend,
    this.requiresMediaOrText = true, // Default: require either text or media
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: compositionService,
      builder: (context, child) {
        final hasText = messageController.text.trim().isNotEmpty;
        final hasMedia = compositionService.hasMedia;
        final isProcessing = compositionService.isProcessingMedia;
        
        // Determine if send button should be enabled
        final isEnabled = !isSending && 
                         !isProcessing && 
                         (requiresMediaOrText ? (hasText || hasMedia) : hasText);

        return CircleAvatar(
          backgroundColor: _getBackgroundColor(context, isEnabled, isProcessing, isSending),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Progress indicator for processing or sending
              if (isProcessing || isSending)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    value: null, // Indeterminate spinner
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),

              // Send icon with different states
              IconButton(
                icon: Icon(
                  _getIcon(isProcessing, isSending),
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: isEnabled ? onSend : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getBackgroundColor(BuildContext context, bool isEnabled, bool isProcessing, bool isSending) {
    if (isEnabled || isProcessing || isSending) {
      return Theme.of(context).colorScheme.primary;
    }
    return Colors.grey.shade400;
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
