import 'dart:io';
import 'package:flutter/foundation.dart';

/// Environment types
enum Environment { development, staging, production }

/// Configuration class to manage environment-specific settings
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();

  factory AppConfig() {
    return _instance;
  }

  AppConfig._internal();

  // Current environment - defaults to development
  Environment _environment = Environment.development;

  // Configurable base URL for the backend API
  String? _customBaseUrl;

  /// Set the current environment
  void setEnvironment(Environment env) {
    _environment = env;
  }

  /// Set a custom base URL (overrides the default for the current environment)
  void setCustomBaseUrl(String url) {
    _customBaseUrl = url;
    debugPrint('AppConfig: Custom URL set to: $_customBaseUrl');
  }

  /// Get the base URL for API requests based on platform and environment
  String get baseUrl {
    // If a custom URL was provided, use it
    if (_customBaseUrl != null) {
      debugPrint('AppConfig: Using custom URL: $_customBaseUrl');
      return _customBaseUrl!;
    }

    String url;
    // Otherwise, choose based on environment and platform
    switch (_environment) {
      case Environment.production:
        url =
            "https://api.familynest.example.com"; // Replace with actual production URL
        debugPrint('AppConfig: Using production URL: $url');
        break;

      case Environment.staging:
        url =
            "https://staging-api.familynest.example.com"; // Replace with actual staging URL
        debugPrint('AppConfig: Using staging URL: $url');
        break;

      case Environment.development:
      default:
        // For development, we need different URLs based on the platform
        if (kIsWeb) {
          url = "http://localhost:8080"; // Use simple localhost for web
          debugPrint('AppConfig: Using web URL: $url');
        } else if (Platform.isAndroid) {
          // Try a different approach for Android - use local network IP
          url =
              "http://10.0.0.81:8080"; // Network IP that works for Android, modified from 10.0.2.2
          debugPrint(
            'AppConfig: Using Android emulator URL: $url (isAndroid: ${Platform.isAndroid})',
          );
        } else if (Platform.isMacOS) {
          // For macOS, use localhost
          url = "http://localhost:8080";
          debugPrint('AppConfig: Using macOS URL: $url');
        } else {
          url = "http://localhost:8080"; // iOS simulator and others
          debugPrint(
            'AppConfig: Using default URL: $url (Platform: ${Platform.operatingSystem})',
          );
        }
        break;
    }
    return url;
  }

  /// Get the base URL for media (images, videos, etc.)
  String get mediaBaseUrl {
    switch (_environment) {
      case Environment.production:
        // In production, media is likely served from a CDN or S3 bucket
        return "https://media.familynest.example.com"; // Replace with actual CDN/S3 URL

      case Environment.staging:
        // In staging, media might be served from a staging S3 bucket
        return "https://staging-media.familynest.example.com"; // Replace with actual staging S3 URL

      case Environment.development:
      default:
        // In development, media is served from the same server as the API
        return baseUrl;
    }
  }

  /// Path configuration that matches the backend application.properties

  /// URL path for videos (matches backend app.url.videos)
  String get videosUrlPath => "/uploads/videos";

  /// URL path for thumbnails (matches backend app.url.thumbnails)
  String get thumbnailsUrlPath => "/uploads/thumbnails";

  /// URL path for images (matches backend app.url.images)
  String get imagesUrlPath => "/uploads/images";

  /// Main uploads URL path
  String get uploadsUrlPath => "/uploads";

  /// Public media path (for alternative access to media files)
  String get publicMediaPath => "/public/media";

  /// Public thumbnails path
  String get publicThumbnailsPath => "/public/media/thumbnails";

  /// Backend project root path - used for sanitizing URLs that contain absolute paths
  /// This path prefix needs to be removed if found in URLs
  String get backendPhysicalPath =>
      "/Users/Anthony/projects/familynest-project/familynest-backend";

  /// Helper method to determine if we're in a production environment
  bool get isProduction => _environment == Environment.production;

  /// Helper method to determine if we're in a development environment
  bool get isDevelopment => _environment == Environment.development;
}
