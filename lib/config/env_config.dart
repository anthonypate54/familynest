import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// A class to handle loading and accessing environment configuration
class EnvConfig {
  static final EnvConfig _instance = EnvConfig._internal();

  factory EnvConfig() {
    return _instance;
  }

  EnvConfig._internal();

  /// Initialize the environment configuration
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
      debugPrint('Loaded environment configuration from .env file');
      debugPrint('API URL: ${EnvConfig().apiUrl}');
      debugPrint('🌍 Environment: ${EnvConfig().environment}');
    } catch (e) {
      debugPrint('$e');
      debugPrint('Falling back to default configuration');
    }
  }

  /// Get the API URL from the environment configuration
  String get apiUrl => dotenv.env['API_URL'] ?? 'http://localhost:8080';

  /// Get the current environment (dev, prod, etc.)
  String get environment => dotenv.env['ENVIRONMENT'] ?? 'dev';

  /// Check if we're in a development environment
  bool get isDevelopment => environment == 'dev';

  /// Check if we're in a production environment
  bool get isProduction => environment == 'prod';
}
