import 'package:flutter/material.dart';
import '../services/link_preview_service.dart';
import 'link_preview_widget.dart';

/// Widget for displaying link preview in the message composition area
class LinkPreviewComposition extends StatelessWidget {
  final LinkPreviewService linkPreviewService;
  final VoidCallback onClose;

  const LinkPreviewComposition({
    Key? key,
    required this.linkPreviewService,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: linkPreviewService,
      builder: (context, child) {
        // Only show the preview in the composition area when actively processing
        // This prevents the duplicate preview at the bottom of the screen
        if (!linkPreviewService.isProcessingLink) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LinkPreviewWidget(
            text: linkPreviewService.detectedUrl ?? '',
            metadata: linkPreviewService.metadata,
            isLoading: linkPreviewService.isProcessingLink,
            errorMessage:
                linkPreviewService.hasError
                    ? linkPreviewService.errorMessage
                    : null,
            onClose: onClose,
          ),
        );
      },
    );
  }
}
