import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Environment types
enum Environment { development, staging, production }

/// Configuration class to manage environment-specific settings
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();

  factory AppConfig() => _instance;

  AppConfig._internal();

  // App environment
  Environment _environment = Environment.development;

  // Cache the platform URL to avoid repeated calculations and prints
  String? _cachedPlatformUrl;

  // API URLs for different environments
  String get _devBaseUrl {
    try {
      if (!dotenv.isInitialized) {
        print(
          '⚠️ dotenv not initialized, using platform-specific default for direct IDE run',
        );
        return _getPlatformDefaultUrl();
      }
      final url = dotenv.env['API_URL'];
      if (url == null || url.isEmpty) {
        print(
          '⚠️ API_URL not found in .env (direct IDE run), using platform default',
        );
        return _getPlatformDefaultUrl();
      }
      print('✅ Using API_URL from .env: $url (run.sh mode)');
      return url;
    } catch (e) {
      print(
        '⚠️ Error reading API_URL from environment, using platform default: $e',
      );
      return _getPlatformDefaultUrl();
    }
  }

  /// Get the correct default URL based on the current platform (for direct IDE runs)
  String _getPlatformDefaultUrl() {
    if (Platform.isAndroid) {
      // We need to detect if this is an emulator or physical device
      // This is async, so we'll use a simple heuristic for now
      // Emulators typically have model names containing "emulator" or "sdk"

      // For now, always try localhost first (works for physical devices with port forwarding)
      // If that fails, the app will handle the error gracefully
      print(
        '📱 Android detected - using localhost with port forwarding: http://localhost:8080',
      );
      print(
        '💡 Make sure adb reverse tcp:8080 tcp:8080 is set up for physical devices',
      );
      print(
        '💡 If this fails, you may need to check emulator vs physical device detection',
      );
      return 'http://localhost:8080';
    } else if (Platform.isIOS) {
      // iOS - use network IP for real devices, localhost for simulator
      print('📱 iOS detected - using network IP: http://10.0.0.9:8080');
      return 'http://10.0.0.9:8080';
    } else {
      // Web/Desktop default
      print('💻 Web/Desktop detected - using localhost:8080');
      return 'http://localhost:8080';
    }
  }

  final String _localDevBaseUrl = 'http://localhost:8080'; // Desktop/iOS
  final String _awsStagingBaseUrl = 'http://54.189.190.245:8080'; // AWS EC2
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

  /// Initialize the configuration
  Future<void> initialize() async {
    // Environment is already set, just print the current configuration
    print('✅ AppConfig initialized');
    print('📡 API URL: ${baseUrl}');
    print(
      '🌍 Environment: ${isDevelopment
          ? "development"
          : isProduction
          ? "production"
          : "staging"}',
    );
  }

  /// Set the current environment
  Future<void> setEnvironment(Environment env) async {
    _environment = env;
    await initialize(); // Reload environment variables
  }

  /// Set a custom base URL (overrides the default for the current environment)
  void setCustomBaseUrl(String url) {
    _customBaseUrl = url;
  }

  /// Get the base URL for API requests based on platform and environment
  String get baseUrl {
    print('🔍 AppConfig.baseUrl called - Current environment: $_environment');

    // If a custom URL was provided, use it
    if (_customBaseUrl != null) {
      print('🔧 Using custom URL: $_customBaseUrl');
      return _customBaseUrl!;
    }

    // Auto-detect environment based on .env API_URL if available
    String apiUrl = _devBaseUrl;
    try {
      if (dotenv.isInitialized) {
        final envUrl = dotenv.env['API_URL'];
        if (envUrl != null && envUrl.isNotEmpty) {
          apiUrl = envUrl;

          // Auto-detect environment based on the URL
          if (apiUrl.contains('54.189.190.245')) {
            if (_environment != Environment.staging) {
              print(
                '🔄 Auto-detected staging environment from API_URL: $apiUrl',
              );
              _environment = Environment.staging;
            }
          } else if (apiUrl.contains('localhost') ||
              apiUrl.contains('127.0.0.1') ||
              apiUrl.contains('10.0.2.2')) {
            if (_environment != Environment.development) {
              print(
                '🔄 Auto-detected development environment from API_URL: $apiUrl',
              );
              _environment = Environment.development;
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Error during environment auto-detection: $e');
    }

    // Otherwise, choose based on environment and platform
    print('🎯 Switching on environment: $_environment');
    switch (_environment) {
      case Environment.production:
        return _prodBaseUrl;

      case Environment.staging:
        return _awsStagingBaseUrl;

      case Environment.development:
      default:
        // For development, always use platform-specific defaults to avoid iOS/Android URL conflicts
        return _devBaseUrl; // Use the cached version
    }
  }

  /// Get the base URL for media (images, videos, etc.)
  String get mediaBaseUrl {
    switch (_environment) {
      case Environment.production:
        return dotenv.env['MEDIA_URL'] ??
            'https://media.familynest.example.com';

      case Environment.staging:
        // For staging, media is served from S3, not the backend server
        return 'https://familynest-staging-media.s3.us-west-2.amazonaws.com';

      case Environment.development:
      default:
        // For development, try to use MEDIA_URL from .env first (for ngrok), then fall back to API base URL
        try {
          if (dotenv.isInitialized) {
            final mediaUrl = dotenv.env['MEDIA_URL'];
            if (mediaUrl != null && mediaUrl.isNotEmpty) {
              print('✅ Using MEDIA_URL from .env: $mediaUrl (ngrok mode)');
              return mediaUrl;
            }
          }
        } catch (e) {
          print('⚠️ Error reading MEDIA_URL from environment: $e');
        }
        // Fallback to same URL as API
        print('🔧 Using API base URL for media (no MEDIA_URL in .env)');
        return _devBaseUrl;
    }
  }

  /// Get the ngrok URL for development
  String get ngrokUrl {
    try {
      if (!dotenv.isInitialized) {
        print(
          '⚠️ dotenv not initialized for ngrok URL, using platform default',
        );
        return _getPlatformDefaultUrl();
      }
      final url = dotenv.env['MEDIA_URL'];
      if (url == null || url.isEmpty) {
        print(
          '⚠️ MEDIA_URL not found in environment variables, using platform default',
        );
        return _getPlatformDefaultUrl();
      }
      return url;
    } catch (e) {
      print(
        '⚠️ Error reading MEDIA_URL from environment, using platform default: $e',
      );
      return _getPlatformDefaultUrl();
    }
  }

  /// Helper method to determine if we're in a production environment
  bool get isProduction => _environment == Environment.production;

  /// Helper method to determine if we're in a development environment
  bool get isDevelopment => _environment == Environment.development;

  // Media Upload Configuration
  /// Maximum file size for direct upload (in MB)
  static const double maxFileUploadSizeMB = 100.0;

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

  // Group Chat Configuration
  /// Maximum number of participants in a group chat (including creator)
  static const int maxGroupChatParticipants = 5;

  /// Minimum number of participants to create a group chat (excluding creator)
  static const int minGroupChatParticipants = 1;

  /// Get the maximum number of participants that can be selected when creating a group
  /// (excludes the creator who is automatically added)
  static int get maxSelectableParticipants => maxGroupChatParticipants - 1;

  /// Get error message for when group size limit is exceeded
  static String getGroupSizeLimitMessage() =>
      'Maximum $maxSelectableParticipants participants allowed ($maxGroupChatParticipants total including you)';
}
