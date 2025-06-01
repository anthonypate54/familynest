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
  }

  /// Get the base URL for API requests based on platform and environment
  /// ngrok http 8080
  String get ngrokUrl =>
      "https://7a1f-2601-1c0-5900-1370-18b4-d181-e92-bbdd.ngrok-free.app";

  ///
  String get baseUrl {
    // If a custom URL was provided, use it
    if (_customBaseUrl != null) {
      return _customBaseUrl!;
    }

    // Otherwise, choose based on environment and platform
    switch (_environment) {
      case Environment.production:
        return "http://api.familynest.example.com"; // Replace with actual production URL

      case Environment.staging:
        return "http://staging-api.familynest.example.com"; // Replace with actual staging URL

      case Environment.development:
      default:
        // For development, we need different URLs based on the platform
        if (kIsWeb) {
          return "https://localhost:8080"; // Use HTTP for web
        } else if (Platform.isAndroid) {
          return "https://10.0.2.2:8080"; // Use HTTP for Android emulator
        } else {
          return "http://localhost:8080"; // Use HTTP for iOS simulator and others
        }
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
}
