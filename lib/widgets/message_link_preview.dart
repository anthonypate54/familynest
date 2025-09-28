import 'package:flutter/material.dart';
import '../widgets/link_preview_widget.dart';
import '../services/link_preview_service.dart';

class MessageLinkPreview extends StatefulWidget {
  final String messageText;

  const MessageLinkPreview({Key? key, required this.messageText})
    : super(key: key);

  @override
  State<MessageLinkPreview> createState() => _MessageLinkPreviewState();
}

class _MessageLinkPreviewState extends State<MessageLinkPreview> {
  String? _url;
  Map<String, dynamic>? _metadata;
  bool _isLoading = false;
  String? _errorMessage;
  final LinkPreviewService _linkPreviewService = LinkPreviewService();

  @override
  void initState() {
    super.initState();
    debugPrint(
      'MessageLinkPreview initState called for text: ${widget.messageText}',
    );
    debugPrint('About to call _extractUrlAndFetchMetadata()');
    _extractUrlAndFetchMetadata();

    // Force immediate fetch for better UI responsiveness
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('Post-frame callback executed, _url: $_url');
      if (_url != null && mounted) {
        _fetchMetadata(_url!);
      }
    });
  }

  @override
  void didUpdateWidget(MessageLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('MessageLinkPreview didUpdateWidget called');
    if (oldWidget.messageText != widget.messageText) {
      debugPrint(
        'Message text changed, about to call _extractUrlAndFetchMetadata()',
      );
      _extractUrlAndFetchMetadata();

      // Force immediate fetch when widget updates
      if (_url != null && mounted) {
        _fetchMetadata(_url!);
      }
    } else {
      debugPrint(
        'Message text unchanged, skipping _extractUrlAndFetchMetadata()',
      );
    }
  }

  void _extractUrlAndFetchMetadata() {
    debugPrint(
      '_extractUrlAndFetchMetadata called with text: ${widget.messageText}',
    );

    // Extract URL from message content
    final urlRegex = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    );
    final match = urlRegex.firstMatch(widget.messageText);

    debugPrint('URL regex match: ${match?.group(0)}');

    if (match != null) {
      final url = match.group(0);
      if (url != null) {
        // Check if we already have cached metadata
        final cachedMetadata = _linkPreviewService.getMetadataForUrl(url);

        if (cachedMetadata != null) {
          // Use cached metadata immediately
          setState(() {
            _url = url;
            _metadata = cachedMetadata;
            _isLoading = false;
          });
        } else {
          // No cached metadata, set loading state
          setState(() {
            _url = url;
            _isLoading = true;
          });

          // Fetch metadata (will be done in post-frame callback)
        }
      }
    }
  }

  Future<void> _fetchMetadata(String url) async {
    debugPrint('_fetchMetadata called for URL: $url');
    try {
      // Use the LinkPreviewService to fetch metadata
      final result = await _linkPreviewService.processUrl(url);
      debugPrint(
        'processUrl result: $result, metadata: ${_linkPreviewService.metadata}',
      );

      if (mounted) {
        setState(() {
          _metadata = _linkPreviewService.metadata;
          _isLoading = false;
          _errorMessage = null;
        });
        debugPrint('State updated with metadata: $_metadata');
      } else {
        debugPrint('Widget no longer mounted, state not updated');
      }
    } catch (e) {
      debugPrint('Error fetching metadata: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        debugPrint('State updated with error: $_errorMessage');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: LinkPreviewWidget(
        text: _url!,
        metadata: _metadata,
        isLoading: _isLoading,
        errorMessage: _errorMessage,
        backgroundColor:
            Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.white,
        primaryTextColor: Theme.of(context).colorScheme.onSurface,
        secondaryTextColor: Theme.of(context).colorScheme.onSurface,
        borderRadius: 8.0,
      ),
    );
  }
}
