import 'dart:io';
import 'package:flutter/foundation.dart';

/// Environment types
enum Environment { development, staging, production }

/// Configuration class to manage environment-specific settings
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();

  factory AppConfig() => _instance;

  AppConfig._internal();

  // App environment
  Environment _environment = Environment.development;

  // API URLs for different environments
  final String _devBaseUrl =
      'http://10.0.2.2:8080'; // Android emulator loopback
  final String _localDevBaseUrl = 'http://localhost:8080'; // Desktop/iOS
  final String _prodBaseUrl = 'https://familynest-api.example.com';

  // Custom URL (set via settings)
  String? _customBaseUrl;

  // Feature flags
  bool enableVideoMessages = true;
  bool enableDMs = true;

  // App settings
  Duration invitationPollingInterval = const Duration(
    minutes: 5,
  ); // Default 5 minutes

  // Set a custom polling interval - useful for testing
  void setInvitationPollingInterval(Duration interval) {
    invitationPollingInterval = interval;
  }

  /// Set the current environment
  void setEnvironment(Environment env) {
    _environment = env;
  }

  /// Set a custom base URL (overrides the default for the current environment)
  void setCustomBaseUrl(String url) {
    _customBaseUrl = url;
  }

  /// Get the base URL for API requests based on platform and environment
  /// ngrok http 8080 --domain=familynest.ngrok.io
  String get ngrokUrl => "https://familynest.ngrok.io";

  ///
  String get baseUrl {
    // If a custom URL was provided, use it
    if (_customBaseUrl != null) {
      return _customBaseUrl!;
    }

    // Otherwise, choose based on environment and platform
    switch (_environment) {
      case Environment.production:
        return _prodBaseUrl;

      case Environment.staging:
        return "http://staging-api.familynest.example.com"; // Replace with actual staging URL

      case Environment.development:
      default:
        // For development, use ngrok for consistent HTTPS access across all platforms
        return ngrokUrl;
    }
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
        return ngrokUrl;
    }
  }

  /// Helper method to determine if we're in a production environment
  bool get isProduction => _environment == Environment.production;

  /// Helper method to determine if we're in a development environment
  bool get isDevelopment => _environment == Environment.development;

  // Media Upload Configuration
  /// Maximum file size for direct upload (in MB)
  static const double maxFileUploadSizeMB = 5.0;

  /// Maximum video duration for uploads (in minutes)
  static const int maxVideoDurationMinutes = 10;

  /// Supported video formats
  static const List<String> supportedVideoFormats = ['mp4', 'mov', 'm4v'];

  /// Supported image formats
  static const List<String> supportedImageFormats = [
    'jpg',
    'jpeg',
    'png',
    'heic',
  ];

  /// Whether to show link sharing option for large files
  static const bool enableLinkSharing = true;
}
