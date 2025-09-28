import 'package:flutter/material.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for handling link preview composition
class LinkPreviewService extends ChangeNotifier {
  // Singleton instance
  static final LinkPreviewService _instance = LinkPreviewService._internal();

  // Factory constructor to return the same instance
  factory LinkPreviewService() {
    return _instance;
  }

  // Internal constructor for singleton
  LinkPreviewService._internal();

  // Cache for metadata
  final Map<String, Map<String, dynamic>> _metadataCache = {};

  // Current link preview state
  String? _detectedUrl;
  bool _isProcessingLink = false;
  Map<String, dynamic>? _metadata;
  bool _hasError = false;
  String? _errorMessage;

  // Getters for current state
  String? get detectedUrl => _detectedUrl;
  bool get isProcessingLink => _isProcessingLink;
  Map<String, dynamic>? get metadata => _metadata;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;

  // Check if we have a link
  bool get hasLink => _detectedUrl != null && _metadata != null;

  // Get metadata for a specific URL from cache
  Map<String, dynamic>? getMetadataForUrl(String url) {
    debugPrint('Checking cache for URL: $url');

    // Try with the original URL
    if (_metadataCache.containsKey(url)) {
      debugPrint('Found metadata in cache for original URL: $url');
      return _metadataCache[url];
    }

    // Try with normalized URL
    final normalizedUrl = normalizeUrl(url);
    if (_metadataCache.containsKey(normalizedUrl)) {
      debugPrint('Found metadata in cache for normalized URL: $normalizedUrl');
      return _metadataCache[normalizedUrl];
    }

    debugPrint('No metadata found in cache for URL: $url');
    return null;
  }

  // Function to normalize URLs
  String normalizeUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'https://$url'; // Prepend https:// if no protocol is present
    }
    return url;
  }

  // Function to extract URLs from text
  List<String> extractUrls(String text) {
    // Use a single comprehensive regex to extract all URLs
    final RegExp urlRegExp = RegExp(
      r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+',
      caseSensitive: false,
    );
    final matches =
        urlRegExp.allMatches(text).map((match) => match.group(0)!).toList();
    //    debugPrint('Extracted URLs: $matches');
    return matches;
  }

  /// Process a URL for preview
  Future<bool> processUrl(String url) async {
    // Normalize the URL first
    final normalizedUrl = normalizeUrl(url);

    // Check if this is a Google Drive link
    final driveFileId = _extractGoogleDriveFileId(normalizedUrl);
    if (driveFileId != null) {
      debugPrint('Detected Google Drive file ID: $driveFileId');
    }

    // Check if we already have metadata in the cache
    if (_metadataCache.containsKey(normalizedUrl)) {
      debugPrint('Using cached metadata for $normalizedUrl');
      _detectedUrl = normalizedUrl;
      _metadata = _metadataCache[normalizedUrl];

      // For Google Drive links, ensure we have a thumbnail URL
      if (driveFileId != null &&
          (_metadata == null || _metadata!['image'] == null)) {
        debugPrint('Enhancing Google Drive metadata with thumbnail');
        final thumbnailUrl = _getGoogleDriveThumbnailUrl(driveFileId);

        if (_metadata != null) {
          _metadata!['image'] = thumbnailUrl;
          // Update the cache with the enhanced metadata
          _metadataCache[normalizedUrl] = _metadata!;
        }
      }

      // Debug the image URL in the cached metadata
      if (_metadata != null && _metadata!['image'] != null) {
        debugPrint('Image URL in cached metadata: ${_metadata!['image']}');
      } else {
        debugPrint('No image URL in cached metadata');
      }

      _isProcessingLink = false;
      _hasError = false;
      _errorMessage = null;
      notifyListeners();
      return true;
    }

    // Skip if it's the same URL we're already processing
    if (_detectedUrl == normalizedUrl && _metadata != null) {
      return true;
    }

    // Prevent multiple simultaneous processing
    if (_isProcessingLink) {
      debugPrint('Already processing link, ignoring duplicate request');
      return false;
    }

    _isProcessingLink = true;
    _detectedUrl = normalizedUrl;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();

    try {
      // Use any_link_preview to fetch metadata
      final metadata = await AnyLinkPreview.getMetadata(
        link: normalizedUrl,
        cache: const Duration(days: 7), // Cache for 7 days
        proxyUrl: "https://corsproxy.org/?", // Use CORS proxy
      );

      debugPrint('Link preview metadata: $metadata');

      // Debug the image URL from the fetched metadata
      if (metadata?.image != null) {
        debugPrint('Image URL from fetched metadata: ${metadata?.image}');
      } else {
        debugPrint('No image URL in fetched metadata');
      }

      // Convert Metadata to Map<String, dynamic>
      final metadataMap = {
        'title': metadata?.title ?? 'Website Link',
        'description': metadata?.desc ?? normalizedUrl,
        'image': metadata?.image,
        'favicon': null, // Favicon not available in Metadata
        'siteName': metadata?.siteName ?? 'Website',
        'host':
            normalizedUrl.contains('://')
                ? normalizedUrl.split('://')[1].split('/')[0]
                : normalizedUrl, // Extract host from URL
        'url': normalizedUrl,
      };

      // Check if this is a Google Drive link and add thumbnail if needed
      final driveFileId = _extractGoogleDriveFileId(normalizedUrl);
      if (driveFileId != null && metadataMap['image'] == null) {
        debugPrint('Adding Google Drive thumbnail for file ID: $driveFileId');
        metadataMap['image'] = _getGoogleDriveThumbnailUrl(driveFileId);
      }

      // Update the cache
      _metadataCache[normalizedUrl] = metadataMap;

      // Update current state
      _metadata = metadataMap;
      _isProcessingLink = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error processing link: $e');
      _hasError = true;
      _errorMessage = e.toString();
      _isProcessingLink = false;
      notifyListeners();
      return false;
    }
  }

  /// Extract Google Drive file ID from URL
  String? _extractGoogleDriveFileId(String url) {
    // Check if it's a Google Drive URL
    if (!url.contains('drive.google.com')) {
      return null;
    }

    try {
      // Handle format: https://drive.google.com/file/d/{fileId}/view?usp=sharing
      final filePattern = RegExp(r'drive\.google\.com/file/d/([^/]+)');
      final fileMatch = filePattern.firstMatch(url);
      if (fileMatch != null && fileMatch.groupCount >= 1) {
        return fileMatch.group(1);
      }

      // Handle format: https://drive.google.com/open?id={fileId}
      if (url.contains('open?id=')) {
        final idIndex = url.indexOf('open?id=');
        if (idIndex != -1) {
          final id = url.substring(idIndex + 8);
          // Handle any additional URL parameters
          final endIndex = id.indexOf('&');
          return endIndex != -1 ? id.substring(0, endIndex) : id;
        }
      }

      // Handle format: https://docs.google.com/document/d/{fileId}/edit
      final docsPattern = RegExp(r'docs\.google\.com/\w+/d/([^/]+)');
      final docsMatch = docsPattern.firstMatch(url);
      if (docsMatch != null && docsMatch.groupCount >= 1) {
        return docsMatch.group(1);
      }
    } catch (e) {
      debugPrint('Error extracting Google Drive file ID: $e');
    }

    return null;
  }

  /// Generate a thumbnail URL for Google Drive file
  String _getGoogleDriveThumbnailUrl(String fileId) {
    // Google Drive thumbnail URL format
    return 'https://drive.google.com/thumbnail?id=$fileId&sz=w320';
  }

  /// Clear the current link preview
  void clearLinkPreview() {
    _detectedUrl = null;
    _metadata = null;
    _isProcessingLink = false;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear the metadata cache for a specific URL
  static void clearCacheForUrl(String url) {
    String normalizedUrl = _instance.normalizeUrl(url);

    // Remove this specific URL from the cache
    if (_instance._metadataCache.containsKey(normalizedUrl)) {
      _instance._metadataCache.remove(normalizedUrl);
      debugPrint('Cache cleared for URL: $normalizedUrl');

      // Reset current state if this was the URL being viewed
      if (_instance._detectedUrl == normalizedUrl) {
        _instance._detectedUrl = null;
        _instance._metadata = null;
        _instance._isProcessingLink = false;
        _instance._hasError = false;
        _instance._errorMessage = null;
        _instance.notifyListeners();
      }
    } else {
      debugPrint('URL not found in cache: $normalizedUrl');
    }
  }

  /// Clear all metadata cache
  static void clearAllCache() {
    debugPrint('Clearing all link preview cache...');
    _instance._metadataCache.clear();
    _instance._detectedUrl = null;
    _instance._metadata = null;
    _instance._isProcessingLink = false;
    _instance._hasError = false;
    _instance._errorMessage = null;
    _instance.notifyListeners();
    debugPrint('All link preview cache cleared');
  }

  /// Build a link preview widget for a message
  /// Returns a widget or null if no URL is found
  Widget? buildLinkPreviewForMessage(
    BuildContext context,
    String messageContent,
  ) {
    // Debug print to see when this method is called
    debugPrint(
      'LinkPreviewService.buildLinkPreviewForMessage called with: $messageContent',
    );

    // Extract URLs from message content
    final urls = extractUrls(messageContent);

    // If no URLs found, return null
    if (urls.isEmpty) {
      debugPrint('No URLs found in message content');
      return null;
    }

    // We don't need to reset metadata for specific URLs anymore

    // Check for metadata in cache first
    Map<String, dynamic>? urlMetadata = getMetadataForUrl(urls.first);

    // If we have cached metadata, use it
    if (urlMetadata != null) {
      _metadata = urlMetadata;
      debugPrint('Using cached metadata for URL: ${urls.first}');
      debugPrint('Image URL in metadata: ${urlMetadata['image']}');
    }
    // If no metadata available yet, start fetching it asynchronously
    else {
      // Start fetching after the build phase completes to avoid setState during build
      debugPrint('No metadata found for URL: ${urls.first}, scheduling fetch');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (urls.isNotEmpty) {
          processUrl(urls.first);
        }
      });
    }

    // Create a Google Messages-style link preview
    return GestureDetector(
      onTap: () {
        // Launch URL when tapped
        try {
          launchUrl(
            Uri.parse(urls.first),
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint('Could not launch URL: ${urls.first} - $e');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8.0),
        decoration: BoxDecoration(
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? Color.fromRGBO(
                    27,
                    94,
                    32,
                    0.8,
                  ) // Green shade 800 with 80% opacity
                  : Colors
                      .green
                      .shade400, // GREEN background for the entire container
          borderRadius: BorderRadius.circular(12.0),
          // No border needed for green container
        ),
        clipBehavior: Clip.antiAlias, // For clean image corners
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No URL display at the top - it's already shown in the message

            // Thumbnail image or placeholder
            Container(
              width: double.infinity,
              height: 200.0,
              color:
                  Theme.of(context).brightness == Brightness.dark
                      ? Color.fromRGBO(
                        27,
                        94,
                        32,
                        0.8,
                      ) // Green shade 800 with 80% opacity
                      : Colors
                          .green
                          .shade400, // GREEN background for image area
              child: Builder(
                builder: (context) {
                  // Debug the image URL before trying to load it
                  if (metadata != null) {
                    debugPrint('Metadata in preview: $metadata');
                    if (metadata!['image'] != null) {
                      final imageUrl = metadata!['image'] as String;
                      debugPrint('Attempting to load image from: $imageUrl');

                      return Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 150.0,
                        errorBuilder: (context, error, stackTrace) {
                          // Log error when image fails to load
                          debugPrint('Error loading image: $error');
                          return Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 50.0,
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey[500]
                                      : Colors.grey[300],
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value:
                                  loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                            ),
                          );
                        },
                      );
                    } else {
                      debugPrint('No image URL in metadata');
                    }
                  } else {
                    debugPrint('No metadata available for preview');
                  }

                  // Fallback to placeholder
                  return Center(
                    child: Icon(
                      Icons.image,
                      size: 50.0,
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[500]
                              : Colors.grey[300],
                    ),
                  );
                },
              ),
            ),

            // Title and metadata in green container
            Container(
              width: double.infinity,
              color:
                  Theme.of(context).brightness == Brightness.dark
                      ? Color.fromRGBO(
                        27,
                        94,
                        32,
                        0.8,
                      ) // Green shade 800 with 80% opacity
                      : Colors.green.shade400,
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    metadata != null && metadata!['title'] != null
                        ? metadata!['title'] as String
                        : "Website Link",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 4.0),

                  // Call to action
                  const Text(
                    "Tap to view!",
                    style: TextStyle(fontSize: 14.0, color: Colors.white),
                  ),

                  const SizedBox(height: 8.0),

                  // Domain
                  Text(
                    metadata != null && metadata!['host'] != null
                        ? metadata!['host'] as String
                        : Uri.parse(urls.first).host,
                    style: const TextStyle(
                      fontSize: 12.0,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
