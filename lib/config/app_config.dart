import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      // Android emulator default (most common for development)
      print(
        '📱 Android detected - using emulator default: http://10.0.2.2:8080',
      );
      return 'http://10.0.2.2:8080';
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
    // If a custom URL was provided, use it
    if (_customBaseUrl != null) {
      return _customBaseUrl!;
    }

    // Otherwise, choose based on environment and platform
    switch (_environment) {
      case Environment.production:
        return _prodBaseUrl;

      case Environment.staging:
        return dotenv.env['API_URL'] ??
            'http://staging-api.familynest.example.com';

      case Environment.development:
      default:
        // For development, always use platform-specific defaults to avoid iOS/Android URL conflicts
        print('🔧 Using platform-specific URL for API in development mode');
        return _getPlatformDefaultUrl();
    }
  }

  /// Get the base URL for media (images, videos, etc.)
  String get mediaBaseUrl {
    switch (_environment) {
      case Environment.production:
        return dotenv.env['MEDIA_URL'] ??
            'https://media.familynest.example.com';

      case Environment.staging:
        return dotenv.env['MEDIA_URL'] ??
            'https://staging-media.familynest.example.com';

      case Environment.development:
      default:
        // For development, always use platform-specific defaults to avoid iOS/Android URL conflicts
        print('🔧 Using platform-specific URL for media in development mode');
        return _getPlatformDefaultUrl();
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
