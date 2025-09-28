import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A widget that displays link preview metadata
class LinkPreviewWidget extends StatefulWidget {
  final String text;
  final Map<String, dynamic>? metadata;
  final Color? backgroundColor;
  final Color? primaryTextColor;
  final Color? secondaryTextColor;
  final double borderRadius;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onClose;

  const LinkPreviewWidget({
    Key? key,
    required this.text,
    this.metadata,
    this.backgroundColor,
    this.primaryTextColor,
    this.secondaryTextColor,
    this.borderRadius = 8.0,
    this.isLoading = false,
    this.errorMessage,
    this.onClose,
  }) : super(key: key);

  @override
  State<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends State<LinkPreviewWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        widget.backgroundColor ??
        (isDark ? Colors.grey[800] : Colors.grey[200]);
    final primaryTextColor =
        widget.primaryTextColor ?? (isDark ? Colors.white : Colors.black);
    final secondaryTextColor =
        widget.secondaryTextColor ??
        (isDark ? Colors.grey[300] : Colors.grey[700]);

    // If we're loading, show a loading indicator
    if (widget.isLoading) {
      return Container(
        margin: const EdgeInsets.only(top: 8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              "Loading link preview...",
              style: TextStyle(color: primaryTextColor, fontSize: 14),
            ),
            if (widget.onClose != null) ...[
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: secondaryTextColor),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      );
    }

    // If we have an error, show the error message
    if (widget.errorMessage != null) {
      return Container(
        margin: const EdgeInsets.only(top: 8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                "Could not load link preview",
                style: TextStyle(color: primaryTextColor, fontSize: 14),
              ),
            ),
            if (widget.onClose != null) ...[
              IconButton(
                icon: Icon(Icons.close, color: secondaryTextColor),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      );
    }

    // If we don't have metadata, show a simple preview
    if (widget.metadata == null) {
      return Container(
        margin: const EdgeInsets.only(top: 8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.link, color: primaryTextColor, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                widget.text,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onClose != null) ...[
              IconButton(
                icon: Icon(Icons.close, color: secondaryTextColor),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      );
    }

    // Extract metadata
    final title = widget.metadata!['title'] as String? ?? 'No title';
    final description = widget.metadata!['description'] as String? ?? '';
    final imageUrl = widget.metadata!['image'] as String?;
    final siteName =
        widget.metadata!['siteName'] as String? ??
        (widget.metadata!['host'] as String? ?? '');
    final favicon = widget.metadata!['favicon'] as String?;

    // Build the preview card
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image if available
          if (imageUrl != null && imageUrl.isNotEmpty)
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => Container(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                    ),
                errorWidget:
                    (context, url, error) => Container(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
              ),
            ),

          // Content
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  title,
                  style: TextStyle(
                    color: primaryTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // Description if available
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: secondaryTextColor, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Site info with favicon
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (favicon != null && favicon.isNotEmpty) ...[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CachedNetworkImage(
                          imageUrl: favicon,
                          placeholder: (context, url) => Container(),
                          errorWidget: (context, url, error) => Container(),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else ...[
                      Icon(Icons.language, size: 14, color: secondaryTextColor),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        siteName,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.onClose != null) ...[
                      IconButton(
                        icon: Icon(Icons.close, color: secondaryTextColor),
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
