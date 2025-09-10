import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../utils/thumbnail_utils.dart';

class ExternalVideoMessageCard extends StatelessWidget {
  final String externalVideoUrl;
  final String? thumbnailUrl;
  final ApiService apiService;

  const ExternalVideoMessageCard({
    super.key,
    required this.externalVideoUrl,
    required this.thumbnailUrl,
    required this.apiService,
  });

  Future<void> _launchExternalVideo() async {
    try {
      final uri = Uri.parse(externalVideoUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch external video URL: $externalVideoUrl');
      }
    } catch (e) {
      debugPrint('Error launching external video: $e');
    }
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey[800]!, Colors.grey[900]!],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.8),
          ),
          const SizedBox(height: 8),
          Text(
            'External Video',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: GestureDetector(
        onTap: _launchExternalVideo,
        child: Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Thumbnail or default background
              if (ThumbnailUtils.isValidThumbnailUrl(thumbnailUrl))
                CachedNetworkImage(
                  imageUrl:
                      thumbnailUrl!.startsWith('http')
                          ? thumbnailUrl!
                          : apiService.mediaBaseUrl + thumbnailUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (context, url) {
                    debugPrint('Loading thumbnail: $url');
                    return Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                  errorWidget: (context, url, error) {
                    // Handle fake/corrupted thumbnails gracefully
                    if (error.toString().contains('Invalid image data') ||
                        error.toString().contains('Image file is corrupted') ||
                        error.toString().contains(
                          'HttpException',
                        ) || // catch any suspiciously small file references
                        error.toString().toLowerCase().contains('format')) {
                      // Show user-friendly message for corrupted thumbnails
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Video thumbnail temporarily unavailable',
                              ),
                              duration: Duration(seconds: 2),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      });
                    }
                    // Always return the default thumbnail, don't log the error
                    return _buildDefaultThumbnail();
                  },
                  httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                )
              else
                _buildDefaultThumbnail(),

              // Play button overlay
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),

              // External indicator badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_outlined, color: Colors.white, size: 12),
                      SizedBox(width: 2),
                      Text(
                        'External',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tap hint (subtle)
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Tap to open',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
