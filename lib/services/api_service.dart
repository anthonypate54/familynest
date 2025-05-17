import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'dart:async';
import 'dart:io' show Platform, File;
import '../config/app_config.dart';
import 'video_upload_service.dart';
import 'dart:math' as Math;

class ApiService {
  // Dynamic baseUrl based on AppConfig
  String get baseUrl {
    final url = AppConfig().baseUrl;
    debugPrint("Using API base URL: $url");
    return url;
  }

  // List of fallback URLs to try
  List<String> _serverFallbacks = [];
  int _currentServerIndex = 0;
  bool _isUsingFallback = false;

  // Get the current server URL (either primary or fallback)
  String get currentServerUrl {
    if (_isUsingFallback &&
        _serverFallbacks.isNotEmpty &&
        _currentServerIndex < _serverFallbacks.length) {
      return _serverFallbacks[_currentServerIndex];
    }
    return baseUrl;
  }

  // Try the next server in the fallback list
  Future<bool> tryNextServer() async {
    if (_serverFallbacks.isEmpty) {
      await _loadServerFallbacks();
    }

    if (_serverFallbacks.isEmpty) {
      return false; // No fallbacks available
    }

    _currentServerIndex = (_currentServerIndex + 1) % _serverFallbacks.length;
    _isUsingFallback = true;
    debugPrint('🔄 Switching to fallback server: ${currentServerUrl}');

    try {
      // Test if this server is reachable
      final response = await client
          .get(
            Uri.parse('${currentServerUrl}/api/users/test'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        debugPrint(
          '✅ Successfully connected to fallback server: ${currentServerUrl}',
        );
        // Update the app config with this working URL
        AppConfig().setCustomBaseUrl(currentServerUrl);
        return true;
      }
    } catch (e) {
      debugPrint(
        '⚠️ Failed to connect to fallback server: ${currentServerUrl}',
      );
    }

    // If we've tried all servers and gone back to the first one, give up
    if (_currentServerIndex == 0) {
      debugPrint('❌ All fallback servers failed');
      return false;
    }

    // Try the next server recursively
    return tryNextServer();
  }

  // Load server fallbacks from SharedPreferences
  Future<void> _loadServerFallbacks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fallbacks = prefs.getStringList('server_fallbacks');
      if (fallbacks != null && fallbacks.isNotEmpty) {
        _serverFallbacks = fallbacks;
        debugPrint(
          '📋 Loaded ${_serverFallbacks.length} server fallbacks: $_serverFallbacks',
        );
      } else {
        debugPrint('⚠️ No server fallbacks found in preferences');
        // Default fallbacks if none are configured
        _serverFallbacks = [
          'http://10.0.0.10:8080',
          'http://10.0.0.81:8080',
          'http://10.0.2.2:8080',
          'http://localhost:8080',
        ];
      }
    } catch (e) {
      debugPrint('❌ Error loading server fallbacks: $e');
    }
  }

  // Media base URL - may be different in production (e.g., CDN)
  String get mediaBaseUrl {
    final url = AppConfig().mediaBaseUrl;
    debugPrint("Using media base URL: $url");
    return url;
  }

  // Special handling for web endpoints in development
  String _getApiEndpoint(String path) {
    if (kIsWeb) {
      // For web, make sure we have the /api prefix
      if (!path.startsWith('/api/')) {
        return '/api$path';
      }
    }
    return path;
  }

  final http.Client client;
  String? _token;

  ApiService({http.Client? client}) : client = client ?? http.Client();

  Future<void> initialize() async {
    // Debug output to track SharedPreferences state
    await debugPrintSharedPrefs("initialize-start");

    // Load fallback servers
    await _loadServerFallbacks();

    await _loadToken();

    // Try to auto-login with any available token
    if (_token != null && _token!.isNotEmpty) {
      try {
        // Verify if the existing token is valid by making a test call
        final currentUser = await getCurrentUser();
        if (currentUser != null) {
          debugPrint('✅ Auto-login successful with existing token');
          return; // Token is valid, initialization successful
        } else {
          debugPrint('⚠️ Saved token is invalid, will try backup methods');
        }
      } catch (e) {
        debugPrint('⚠️ Error validating stored token: $e');
      }

      // We no longer use test tokens
      if (kDebugMode) {
        debugPrint('⚠️ Token is invalid and we no longer use test tokens');
      }
    }

    // Test connection if no valid token was found
    try {
      await testConnection();
    } catch (e) {
      debugPrint('❌ Connection test failed with error: $e');
      // Try fallback servers
      if (await tryNextServer()) {
        // If a fallback works, test connection again
        try {
          await testConnection();
        } catch (fallbackError) {
          debugPrint('❌ All fallback servers failed: $fallbackError');
          rethrow;
        }
      } else {
        debugPrint('''
❌ Connection test failed with all servers. Please check:
1. Is the backend server running? ($baseUrl/api/users/test)
2. Are you using the correct IP address?
   - Android Emulator: 10.0.0.81
   - iOS Simulator: prefs.getString('user_id');
   - Physical Device: Your computer's local IP
3. Is your device/emulator connected to the same network?
4. Are there any firewall settings blocking the connection?
''');
        rethrow;
      }
    }
  }

  Future<void> testConnection() async {
    debugPrint('Testing connection to $currentServerUrl');
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _makeRequest(
        'GET',
        '/api/users/test',
        headers: {'Accept': 'application/json'},
        maxRetries: 2,
      );

      stopwatch.stop();
      debugPrint(
        'Connection test completed in ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ Connection test successful on server: $currentServerUrl');
      } else {
        debugPrint(
          '❌ Connection test failed with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('❌ Connection test failed with error: $e');
      debugPrint('''
Network connection error. Please check:
1. Is the backend server running? ($currentServerUrl/api/users/test)
2. Are you using the correct IP address?
   - Android Emulator: 10.0.0.81
   - iOS Simulator: localhost
   - Physical Device: Your computer's local IP
3. Is your device/emulator connected to the same network?
4. Are there any firewall settings blocking the connection?
''');
      rethrow;
    }
  }

  Future<void> _loadToken() async {
    // Debug output to track SharedPreferences state
    await debugPrintSharedPrefs("_loadToken-start");

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if shared preferences contains our token
      final keys = prefs.getKeys();
      debugPrint('All SharedPreferences keys: $keys');

      // Try to retrieve token from both primary and backup locations
      _token = prefs.getString('auth_token');

      // If primary token is missing, try the backup token
      if (_token == null || _token!.isEmpty) {
        _token = prefs.getString('auth_token_backup');
        if (_token != null && _token!.isNotEmpty) {
          debugPrint('Using backup token since primary token was missing');
          // Restore primary token
          await prefs.setString('auth_token', _token!);
        }
      }

      // For debugging builds, if no token is found, try to fetch a test token
      if ((_token == null || _token!.isEmpty) && kDebugMode) {
        debugPrint('No token found in storage, trying to get a test token');
        // Will fetch a test token in the initialize method
      } else if (_token != null && _token!.isNotEmpty) {
        debugPrint(
          'Loaded token from storage: ${_token!.substring(0, Math.min(10, _token!.length))}...',
        );
      } else {
        debugPrint('No token found in storage');
      }
    } catch (e) {
      debugPrint('Error loading token: $e');
      _token = null;
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear any existing tokens first
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');

      // Save with two different keys for redundancy
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_token_backup', token);

      _token = token;
      debugPrint(
        'Saved token to storage: ${token.substring(0, Math.min(10, token.length))}...',
      );

      // Verify token was saved
      final savedToken = prefs.getString('auth_token');
      final backupToken = prefs.getString('auth_token_backup');

      if (savedToken != null && savedToken.isNotEmpty) {
        debugPrint(
          '✅ Primary token saved successfully (${savedToken.length} chars)',
        );
      } else {
        debugPrint('❌ ERROR: Primary token not saved!');
      }

      if (backupToken != null && backupToken.isNotEmpty) {
        debugPrint(
          '✅ Backup token saved successfully (${backupToken.length} chars)',
        );
      } else {
        debugPrint('❌ ERROR: Backup token not saved!');
      }

      // Save the token timestamp for debugging
      await prefs.setString(
        'token_save_time',
        DateTime.now().toIso8601String(),
      );

      // Simple verification of any existing user_id
      final userId = prefs.getString('user_id');
      if (userId != null && userId.isNotEmpty) {
        debugPrint('✓ Verified existing user_id: $userId');
      }
    } catch (e) {
      debugPrint('Error saving token: $e');
    }
  }

  Future<void> _clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear token data
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');
      await prefs.remove('token_save_time');

      // Clear additional login data
      await prefs.remove('user_id');
      await prefs.remove('user_role');
      await prefs.remove('is_logged_in');
      await prefs.remove('login_time');

      _token = null;
      debugPrint('Cleared all auth data from storage');
    } catch (e) {
      debugPrint('Error clearing token: $e');
    }
  }

  // Helper method to safely parse user ID from string with optional default value
  int? _safeParseId(String? idStr, {int? defaultValue}) {
    if (idStr == null || idStr.isEmpty) {
      return defaultValue; // No hardcoded fallback
    }
    try {
      final parsedId = int.parse(idStr);
      return parsedId;
    } catch (e) {
      return defaultValue; // No hardcoded fallback
    }
  }

  // Debug helper to print the current state of SharedPreferences
  Future<void> debugPrintSharedPrefs(String location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      debugPrint('📋 SHARED PREFERENCES STATE AT "$location":');
      debugPrint('  All keys: $keys');

      if (keys.contains('user_id')) {
        final userId = prefs.getString('user_id');
        debugPrint('  user_id = "$userId"');
      } else {
        debugPrint('  ⚠️ user_id KEY NOT FOUND!');
      }

      if (keys.contains('auth_token')) {
        final token = prefs.getString('auth_token');
        if (token != null && token.isNotEmpty) {
          debugPrint('  auth_token exists with length: ${token.length}');
        } else {
          debugPrint('  auth_token exists but is empty');
        }
      }

      if (keys.contains('is_logged_in')) {
        debugPrint('  is_logged_in = ${prefs.getBool('is_logged_in')}');
      }
    } catch (e) {
      debugPrint('❌ Error printing SharedPreferences: $e');
    }
  }

  // Helper method to safely set a value in SharedPreferences with verification
  Future<bool> _safeSetPrefs(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    try {
      // Set the value
      final success = await prefs.setString(key, value);

      // Verify the value was saved
      final savedValue = prefs.getString(key);
      if (savedValue == value) {
        debugPrint('✅ Successfully saved "$key" with value: $value');
        return true;
      } else {
        debugPrint('❌ Failed to save "$key" - value mismatch or not saved');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error saving "$key": $e');
      return false;
    }
  }

  // Login method to authenticate a user
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      debugPrint('🧪 Attempting login for email: $email');
      debugPrint('🧪 Using base URL: $baseUrl');

      // Check if we already have shared preferences available
      final prefs = await SharedPreferences.getInstance();
      final prefsKeys = prefs.getKeys();
      debugPrint('🧪 SharedPreferences before login: $prefsKeys');

      // Clear any existing tokens to start fresh
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');
      await prefs.remove('token_save_time');

      debugPrint(
        '🧪 Sending login request to: $currentServerUrl/api/users/login',
      );

      // Use our new helper method with automatic fallback
      final response = await _makeRequest(
        'POST',
        '/api/users/login',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'email': email, 'password': password}),
        maxRetries: 3, // Try more servers for login
      );

      debugPrint('🧪 Login response status: ${response.statusCode}');
      debugPrint('🧪 Response headers: ${response.headers}');
      if (response.body.length < 1000) {
        // Only print full body if it's not too large
        debugPrint('🧪 Response body: ${response.body}');
      } else {
        debugPrint(
          '🧪 Response body: (truncated) ${response.body.substring(0, 500)}...',
        );
      }

      if (response.statusCode == 200) {
        debugPrint('✅ Login successful, parsing response');
        try {
          final data = json.decode(response.body);

          debugPrint('Login response: $data');

          if (data['token'] != null) {
            // Save token using the _saveToken method
            final String token = data['token'];
            await _saveToken(token);

            // Double verification step - read it back directly after save
            final verifyToken = prefs.getString('auth_token');
            if (verifyToken != token) {
              debugPrint(
                '⚠️ CRITICAL: Token verification failed! Trying again...',
              );

              // Try once more with direct prefs calls
              await prefs.setString('auth_token', token);
              await prefs.setString('auth_token_backup', token);
              debugPrint('Forced token save a second time');

              // Store user_id with extra validation
              if (data['userId'] != null) {
                final userIdStr = data['userId'].toString();

                // First set the user_id with extra safety measures
                await prefs.setString('user_id', userIdStr);
                // Always set is_logged_in flag so we know the user has been authenticated
                await prefs.setBool('is_logged_in', true);
                // Also store the role
                await prefs.setString('user_role', data['role'] ?? 'USER');
                await prefs.setString(
                  'login_time',
                  DateTime.now().toIso8601String(),
                );

                // Verify user_id was actually saved (critical for auto-login)
                final storedUserId = prefs.getString('user_id');
                if (storedUserId != userIdStr) {
                  debugPrint(
                    '⚠️ CRITICAL: user_id verification failed! Retrying...',
                  );

                  // Try one more time with forced persistance
                  await prefs.remove('user_id'); // First remove completely
                  await Future.delayed(
                    const Duration(milliseconds: 100),
                  ); // Brief delay
                  await prefs.setString('user_id', userIdStr); // Set again

                  // Double-check again
                  final finalCheck = prefs.getString('user_id');
                  if (finalCheck != userIdStr) {
                    debugPrint(
                      '⚠️ CRITICAL: user_id still not saved after retry!',
                    );
                  } else {
                    debugPrint('✅ user_id saved on second attempt');
                  }
                } else {
                  debugPrint('✅ user_id saved successfully on first attempt');
                }

                debugPrint(
                  '💾 Stored user_id in SharedPreferences: ${data['userId']}',
                );

                // Verify all credentials were saved
                final isLoggedIn = prefs.getBool('is_logged_in');
                final userRole = prefs.getString('user_role');
                debugPrint(
                  '✓ Credential verification: user_id=$storedUserId, is_logged_in=$isLoggedIn, role=$userRole',
                );
              } else {
                debugPrint('⚠️ WARNING: No userId in login response!');
              }

              await prefs.setString('user_role', data['role'] ?? 'USER');
              await prefs.setBool('is_logged_in', true);
              await prefs.setString(
                'login_time',
                DateTime.now().toIso8601String(),
              );

              // Double-check that user_id was actually written to SharedPreferences
              final storedUserId = prefs.getString('user_id');
              final storedLoggedIn = prefs.getBool('is_logged_in');
              debugPrint(
                '🔍 VERIFICATION - Stored user_id: "$storedUserId", is_logged_in: $storedLoggedIn',
              );

              // Verify again
              final secondVerifyToken = prefs.getString('auth_token');
              if (secondVerifyToken == token) {
                debugPrint('✅ Token successfully saved on second attempt');
              } else {
                debugPrint(
                  '❌ CRITICAL ERROR: Token could not be saved after multiple attempts',
                );
              }
            } else {
              debugPrint('✅ Token verification successful');

              // Store additional user data for backup login with extra validation
              if (data['userId'] != null) {
                final userIdStr = data['userId'].toString();

                // First set the user_id with extra safety measures
                await prefs.setString('user_id', userIdStr);
                // Always set is_logged_in flag so we know the user has been authenticated
                await prefs.setBool('is_logged_in', true);
                // Also store the role
                await prefs.setString('user_role', data['role'] ?? 'USER');
                await prefs.setString(
                  'login_time',
                  DateTime.now().toIso8601String(),
                );

                // Verify user_id was actually saved (critical for auto-login)
                final storedUserId = prefs.getString('user_id');
                if (storedUserId != userIdStr) {
                  debugPrint(
                    '⚠️ CRITICAL: user_id verification failed! Retrying...',
                  );

                  // Try one more time with forced persistance
                  await prefs.remove('user_id'); // First remove completely
                  await Future.delayed(
                    const Duration(milliseconds: 100),
                  ); // Brief delay
                  await prefs.setString('user_id', userIdStr); // Set again

                  // Double-check again
                  final finalCheck = prefs.getString('user_id');
                  if (finalCheck != userIdStr) {
                    debugPrint(
                      '⚠️ CRITICAL: user_id still not saved after retry!',
                    );
                  } else {
                    debugPrint('✅ user_id saved on second attempt');
                  }
                } else {
                  debugPrint('✅ user_id saved successfully on first attempt');
                }

                debugPrint(
                  '💾 Stored user_id in SharedPreferences: ${data['userId']}',
                );

                // Verify all credentials were saved
                final isLoggedIn = prefs.getBool('is_logged_in');
                final userRole = prefs.getString('user_role');
                debugPrint(
                  '✓ Credential verification: user_id=$storedUserId, is_logged_in=$isLoggedIn, role=$userRole',
                );
              } else {
                debugPrint('⚠️ WARNING: No userId in login response!');
              }

              await prefs.setString('user_role', data['role'] ?? 'USER');
              await prefs.setBool('is_logged_in', true);
              await prefs.setString(
                'login_time',
                DateTime.now().toIso8601String(),
              );
            }

            // Ensure _token is set in memory
            _token = token;

            return data;
          } else {
            debugPrint('⚠️ WARNING: No token in login response!');
            return data; // Still return the data, but it may not allow auto-login next time
          }
        } catch (e) {
          debugPrint('Error parsing login response: $e');
          debugPrint('Response body was: ${response.body}');
          return null;
        }
      } else {
        debugPrint('Login failed with status code: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception during login: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    // Debug output to track SharedPreferences state
    await debugPrintSharedPrefs("getCurrentUser-start");

    debugPrint(
      'Checking for current user, token: ${_token != null ? "${_token!.substring(0, Math.min(10, _token!.length))}..." : "null"}',
    );

    try {
      final prefs = await SharedPreferences.getInstance();

      // CRITICAL FIX: Check for user_id persistence issues
      final allKeys = prefs.getKeys();
      debugPrint('📋 SHARED PREFERENCES CURRENT STATE:');
      debugPrint('All keys: $allKeys');

      String? persistedUserId;
      if (allKeys.contains('user_id')) {
        final rawUserId = prefs.getString('user_id');
        debugPrint('user_id value: "$rawUserId"');

        // Extra defensive check - if user_id is empty string or "null" string, treat as null
        if (rawUserId == null ||
            rawUserId.isEmpty ||
            rawUserId.toLowerCase() == "null") {
          debugPrint(
            '⚠️ user_id is empty or "null" string in SharedPreferences!',
          );

          // In debug mode, automatically set a test user ID
          if (kDebugMode) {
            await prefs.setString('user_id', '101');
            await prefs.setBool('is_logged_in', true);
            await prefs.setString('user_role', 'USER');
            debugPrint('🔧 DEBUG MODE: Set test user ID 101 for development');
          }
        }
      } else {
        debugPrint('⚠️ user_id KEY NOT FOUND in SharedPreferences!');

        // In debug mode, automatically set a test user ID
        if (kDebugMode) {
          await prefs.setString('user_id', '101');
          await prefs.setBool('is_logged_in', true);
          await prefs.setString('user_role', 'USER');
          debugPrint('🔧 DEBUG MODE: Set test user ID 101 for development');
        }
      }
      if (allKeys.contains('is_logged_in')) {
        debugPrint('is_logged_in value: ${prefs.getBool('is_logged_in')}');
      }
      if (allKeys.contains('auth_token')) {
        final token = prefs.getString('auth_token');
        debugPrint('auth_token exists with length: ${token?.length ?? 0}');
      }

      // Check if we have a valid token
      if (_token == null || _token!.isEmpty) {
        debugPrint('No token available, checking for backup login info');

        // Check if we have backup login info
        final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
        final userIdStr = prefs.getString('user_id');
        final userRole = prefs.getString('user_role');

        // Extra check to explicitly handle empty string or "null" string
        final validUserIdStr =
            (userIdStr == null ||
                    userIdStr.isEmpty ||
                    userIdStr.toLowerCase() == "null")
                ? null
                : userIdStr;

        // No default values, just parse what we have
        final userId = _safeParseId(validUserIdStr);

        // In debug mode, we'll accept missing login status too, but only if userId is valid
        final effectiveIsLoggedIn =
            userId != null && (kDebugMode || isLoggedIn);

        if (effectiveIsLoggedIn) {
          debugPrint(
            '🔄 Found backup login info, attempting to restore session',
          );

          // For development builds, try to get a fresh test token
          if (kDebugMode) {
            debugPrint('🔑 Using stored credentials in debug mode');
            // Skip token checks in debug mode and just use the saved user ID
            return {'userId': userId, 'role': userRole ?? 'USER'};
          }

          // Return the user info from backup
          debugPrint('🔄 Returning user data from backup login info');
          return {'userId': userId, 'role': userRole ?? 'USER'};
        }

        debugPrint('No backup login info available');
        return null;
      }

      // Try to validate token with the server using the current server URL (with fallback support)
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };
      final currentUserPath = _getApiEndpoint('/api/users/current');

      debugPrint(
        'Sending request to ${currentServerUrl}$currentUserPath with token: ${_token!.substring(0, Math.min(10, _token!.length))}...',
      );

      // Try up to 2 server fallbacks if needed
      http.Response? response;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          response = await client.get(
            Uri.parse('${currentServerUrl}$currentUserPath'),
            headers: headers,
          );
          // If successful, break out of the loop
          break;
        } catch (e) {
          debugPrint('Error on attempt $attempt: $e');
          if (attempt < 2 && await tryNextServer()) {
            debugPrint('Trying next server...');
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        throw Exception('Failed to connect to any server');
      }
      debugPrint(
        'Get current user response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;

        debugPrint('✅ Current user validated successfully');

        // Update backup info with fresh data
        await prefs.setString(
          'user_id',
          responseBody['userId']?.toString() ?? "",
        );
        debugPrint(
          '💾 Updated user_id in SharedPreferences: ${responseBody['userId']}',
        );
        await prefs.setString('user_role', responseBody['role'] ?? 'USER');
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('login_time', DateTime.now().toIso8601String());

        // Safely handle userId - no default values
        int? userId;
        if (responseBody['userId'] != null) {
          // Try to convert to int safely
          try {
            userId = (responseBody['userId'] as num).toInt();

            // Store the value back to preferences explicitly
            await prefs.setString('user_id', userId.toString());
            debugPrint('Saved userId to preferences: $userId');
          } catch (e) {
            // If we get a type error, try to handle it gracefully
            debugPrint('Error converting userId: $e');

            // Try parsing as string
            try {
              userId = int.parse(responseBody['userId'].toString());
              await prefs.setString('user_id', userId.toString());
            } catch (e2) {
              debugPrint('Failed to parse userId as int: $e2');
            }
          }
        } else {
          // Try to get userId from preferences
          final storedId = prefs.getString('user_id');
          if (storedId != null && storedId.isNotEmpty) {
            try {
              userId = int.parse(storedId);
              debugPrint('Using stored userId: $userId');
            } catch (e) {
              debugPrint('Failed to parse stored userId: $e');
            }
          }
        }

        // If we have a valid userId, return the user data
        if (userId != null) {
          return {
            'userId': userId,
            'role': responseBody['role'] as String? ?? 'USER',
          };
        } else {
          // No valid userId, log and return null
          debugPrint('No valid userId found in response or preferences');
          return null;
        }
      } else {
        debugPrint('❌ Invalid token, checking for backup login info');

        // Check if we have backup login info
        final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
        final userIdStr = prefs.getString('user_id');
        final userRole = prefs.getString('user_role');

        // Extra check to explicitly handle empty string or "null" string
        final validUserIdStr =
            (userIdStr == null ||
                    userIdStr.isEmpty ||
                    userIdStr.toLowerCase() == "null")
                ? null
                : userIdStr;

        // No default values, just parse what we have
        final userId = _safeParseId(validUserIdStr);

        // In debug mode, we'll accept missing login status too, but only if userId is valid
        final effectiveIsLoggedIn =
            userId != null && (kDebugMode || isLoggedIn);

        if (effectiveIsLoggedIn) {
          debugPrint(
            '🔄 Found backup login info, attempting to restore session',
          );

          // For development builds, try to get a fresh test token
          if (kDebugMode) {
            debugPrint('🔑 Using stored credentials in debug mode');
            // Skip token checks in debug mode and just use the saved user ID
            return {'userId': userId, 'role': userRole ?? 'USER'};
          }

          // Return the user info from backup
          debugPrint('🔄 Returning user data from backup login info');
          return {'userId': userId, 'role': userRole ?? 'USER'};
        }

        debugPrint('No valid backup login info, clearing token');
        await _clearToken();
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error getting current user: $e');

      // Check if we have backup login info
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final userIdStr = prefs.getString('user_id');
      final userRole = prefs.getString('user_role');

      // Extra check to explicitly handle empty string or "null" string
      final validUserIdStr =
          (userIdStr == null ||
                  userIdStr.isEmpty ||
                  userIdStr.toLowerCase() == "null")
              ? null
              : userIdStr;

      // No default values, just parse what we have
      final userId = _safeParseId(validUserIdStr);

      // In debug mode, we'll accept missing login status too, but only if userId is valid
      final effectiveIsLoggedIn = userId != null && (kDebugMode || isLoggedIn);

      if (effectiveIsLoggedIn) {
        debugPrint('🔄 Network error but found backup login info');

        // We no longer use test tokens
        if (kDebugMode) {
          debugPrint('🔄 Using saved credentials without test token');
        }

        // Return the user info from backup during network errors
        debugPrint(
          '🔄 Returning user data from backup login info during network error',
        );
        return {'userId': userId, 'role': userRole ?? 'USER'};
      }

      // Don't clear token on network errors, only on auth errors
      if (e.toString().contains('401') || e.toString().contains('403')) {
        debugPrint('Auth error, clearing token');
        await _clearToken();
      } else {
        debugPrint('Network error, keeping token');
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> registerUser({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String userRole = 'USER',
    String? photoPath,
    Map<String, dynamic>? demographics,
  }) async {
    await initialize();
    try {
      debugPrint('Attempting to register user: $username');

      // Check photo size before attempting to upload
      if (photoPath != null && !kIsWeb) {
        final file = File(photoPath);
        if (await file.exists()) {
          final fileSize = await file.length();
          final fileSizeKB = fileSize ~/ 1024;
          debugPrint('Photo file size: $fileSizeKB KB');

          // If file is larger than 1MB, throw an error
          if (fileSize > 1 * 1024 * 1024) {
            debugPrint('File size too large: $fileSizeKB KB (max 1MB)');
            throw Exception(
              'Profile photo is too large (${fileSizeKB}KB). Please select a smaller image or use the photo with compression.',
            );
          }
        } else {
          debugPrint('Photo file does not exist at path: $photoPath');
          photoPath = null; // Reset path if file doesn't exist
        }
      }

      final registerPath = _getApiEndpoint('/api/users');
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl$registerPath'),
      );

      // Combine basic user data with demographic data
      final userData = {
        'username': username,
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'role': userRole,
      };

      // Add demographics data if provided
      if (demographics != null) {
        userData.addAll({
          'phoneNumber': demographics['phoneNumber'],
          'address': demographics['address'],
          'city': demographics['city'],
          'state': demographics['state'],
          'zipCode': demographics['zipCode'],
          'country': demographics['country'],
          'birthDate': demographics['birthDate'],
          'bio': demographics['bio'],
          'showDemographics': demographics['showDemographics'],
        });
      }

      request.fields['userData'] = jsonEncode(userData);

      if (photoPath != null && !kIsWeb) {
        try {
          debugPrint('Adding photo to request: $photoPath');
          request.files.add(
            await http.MultipartFile.fromPath('photo', photoPath),
          );
          debugPrint('Successfully added photo to request');
        } catch (e) {
          debugPrint('Error adding photo to request: $e');
          // Continue without photo if there's an error
        }
      }

      debugPrint('Sending registration request to: ${request.url}');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      debugPrint(
        'Register response: statusCode=${response.statusCode}, body=$responseBody',
      );
      if (response.statusCode == 201) {
        final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
        return {'userId': (responseData['userId'] as num).toInt()};
      } else {
        throw Exception(
          'Failed to register: statusCode=${response.statusCode}, body=$responseBody',
        );
      }
    } catch (e) {
      debugPrint('Register failed with error: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    debugPrint('Logging out, clearing all auth data');

    try {
      // Try to call logout endpoint if available
      if (_token != null) {
        try {
          final response = await client.post(
            Uri.parse('$baseUrl/api/users/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
          );
          debugPrint('Server logout response: ${response.statusCode}');
        } catch (e) {
          debugPrint('Error calling server logout (continuing anyway): $e');
        }
      }
    } finally {
      // Always clear local token data regardless of server response
      await _clearToken();
    }
  }

  Future<Map<String, dynamic>> updateDemographics(
    int userId,
    Map<String, dynamic> demographicsData,
  ) async {
    final headers = {'Content-Type': 'application/json'};

    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    debugPrint(
      'Updating demographics for user ID: $userId with data: $demographicsData',
    );

    try {
      // Try a different endpoint path since the current one returns 404
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/profile'),
        headers: headers,
        body: jsonEncode(demographicsData),
      );

      debugPrint(
        'Update demographics response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to update demographics: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error updating demographics: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getUserById(int id) async {
    final headers = {'Content-Type': 'application/json'};
    debugPrint('getUserById: Getting user with ID: $id');
    debugPrint('Token in getUserById: $_token');
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      debugPrint('Authorization header set: Bearer $_token');
    } else {
      debugPrint('No token available, Authorization header not set');
    }

    try {
      debugPrint('Sending request to $baseUrl/api/users/$id');
      final response = await client.get(
        Uri.parse('$baseUrl/api/users/$id'),
        headers: headers,
      );
      debugPrint(
        'Get user response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('User data successfully retrieved: $userData');

        // Log photo URL information
        print('👤 USER DATA FOR ID $id:');
        print('Keys in user data: ${userData.keys.join(', ')}');

        // Check for photoUrl
        if (userData.containsKey('photoUrl')) {
          print('📸 photoUrl: ${userData['photoUrl']}');
          if (userData['photoUrl'] != null) {
            final String fullUrl =
                userData['photoUrl'].startsWith('http')
                    ? userData['photoUrl']
                    : '$baseUrl${userData['photoUrl']}';
            print('Full photo URL: $fullUrl');
          }
        }

        // Look for any keys containing photo
        final photoRelatedKeys =
            userData.keys
                .where(
                  (key) =>
                      key.toLowerCase().contains('photo') ||
                      key.toLowerCase().contains('image') ||
                      key.toLowerCase().contains('avatar'),
                )
                .toList();

        if (photoRelatedKeys.isNotEmpty) {
          print('📸 POTENTIAL PHOTO FIELDS IN USER DATA:');
          for (final key in photoRelatedKeys) {
            print('$key: ${userData[key]}');
          }
        } else {
          print('⚠️ NO PHOTO-RELATED FIELDS FOUND IN USER DATA');
        }

        // Explicitly log the familyId for debugging
        debugPrint('Family ID for user $id: ${userData['familyId']}');

        return userData;
      } else {
        debugPrint('Error getting user: ${response.statusCode}');
        throw Exception(
          'Failed to get user details: statusCode=${response.statusCode}, body=${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Exception in getUserById: $e');
      rethrow;
    }
  }

  Future<int> createFamily(int userId, String familyName) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/create-family'),
      headers: headers,
      body: jsonEncode({'name': familyName, 'leaveCurrentFamily': true}),
    );
    if (response.statusCode == 201) {
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      return (responseBody['familyId'] as num).toInt();
    } else {
      throw Exception('Failed to create family: ${response.body}');
    }
  }

  Future<void> joinFamily(int userId, int familyId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    debugPrint(
      'Attempting to join family: User ID: $userId, Family ID: $familyId',
    );

    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/join-family/$familyId'),
        headers: headers,
      );

      debugPrint(
        'Join family response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode != 200) {
        String errorMessage = 'Failed to join family';

        // Try to parse the error message from the response body
        if (response.body.isNotEmpty) {
          try {
            final responseBody = jsonDecode(response.body);
            if (responseBody is Map && responseBody.containsKey('error')) {
              errorMessage = responseBody['error'];
            }
          } catch (e) {
            // If parsing fails, just use the raw body
            debugPrint('Error parsing response body: $e');
            errorMessage = response.body;
          }
        }

        // Add specific error messages based on the response or known conditions
        if (errorMessage.contains('already belongs to a family')) {
          errorMessage = 'User already belongs to a family';
        } else if (response.statusCode == 404 ||
            errorMessage.contains('not found')) {
          errorMessage = 'Family not found';
        }

        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('Error joining family: $e');
      rethrow;
    }
  }

  // Handle video file upload with backend thumbnail generation
  Future<Map<String, String>> uploadVideoWithThumbnail(File videoFile) async {
    debugPrint('Uploading video for processing: ${videoFile.path}');
    final url = '$baseUrl/api/videos/upload';

    try {
      var request = http.MultipartRequest('POST', Uri.parse(url));

      // Add the auth token
      request.headers['Authorization'] = 'Bearer $_token';

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath('file', videoFile.path),
      );

      debugPrint('Sending video upload request to: $url');
      var response = await request.send();

      if (response.statusCode == 200) {
        final String responseBody = await response.stream.bytesToString();
        debugPrint('Video processing response: $responseBody');

        final Map<String, dynamic> data = json.decode(responseBody);

        // Get the video and thumbnail URLs
        final String videoUrl = data['videoUrl'] ?? '';
        final String thumbnailUrl = data['thumbnailUrl'] ?? '';

        // Convert relative URLs to absolute URLs
        final String fullVideoUrl =
            videoUrl.startsWith('http') ? videoUrl : '$baseUrl$videoUrl';

        final String fullThumbnailUrl =
            thumbnailUrl.startsWith('http')
                ? thumbnailUrl
                : '$baseUrl$thumbnailUrl';

        debugPrint('Video URL: $fullVideoUrl');
        debugPrint('Thumbnail URL: $fullThumbnailUrl');

        return {'videoUrl': fullVideoUrl, 'thumbnailUrl': fullThumbnailUrl};
      } else {
        final String responseBody = await response.stream.bytesToString();
        debugPrint(
          'Video upload failed with status ${response.statusCode}: $responseBody',
        );
        return {};
      }
    } catch (e) {
      debugPrint('Error uploading video: $e');
      return {};
    }
  }

  // Get full URL for a thumbnail - can use public endpoint if available
  String getThumbnailUrl(String thumbnailPath) {
    // If it's already a full URL, return it as is
    if (thumbnailPath.startsWith('http')) {
      return thumbnailPath;
    }

    // If it's a relative path
    if (thumbnailPath.startsWith('/')) {
      // Extract just the filename from the path for our special endpoint
      final String filename = thumbnailPath.substring(
        thumbnailPath.lastIndexOf('/') + 1,
      );

      // Use our special direct thumbnail endpoint
      return '$baseUrl/api/videos/public/thumbnail/$filename';
    }

    // If it's just a filename, assume it's a thumbnail
    if (!thumbnailPath.contains('/')) {
      return '$baseUrl/api/videos/public/thumbnail/$thumbnailPath';
    }

    // Default to just adding the base URL
    return '$baseUrl$thumbnailPath';
  }

  // Integrate backend video upload with message posting
  Future<bool> postMessageWithVideoProcessing(
    int userId,
    String content, {
    String? mediaPath,
    String? mediaType,
    int? familyId,
  }) async {
    // Handle video upload with thumbnail generation if this is a video
    Map<String, String>? videoData;
    String? effectiveMediaPath = mediaPath;

    if (mediaPath != null && mediaType == 'video' && !kIsWeb) {
      try {
        debugPrint('Processing video before posting message');
        final videoFile = File(mediaPath);

        // Upload to backend for processing
        videoData = await uploadVideoWithThumbnail(videoFile);

        // If we got a successful remote URL, use that instead of the local file
        if (videoData['videoUrl'] != null &&
            videoData['videoUrl']!.isNotEmpty &&
            videoData['videoUrl']!.startsWith('http')) {
          // Use the remote URL instead of the local file
          effectiveMediaPath = null; // Don't send local file
          debugPrint('Using remote video URL: ${videoData['videoUrl']}');
        } else {
          // Fall back to original local file
          debugPrint('Falling back to local video file');
        }
      } catch (e) {
        debugPrint('Error processing video: $e');
        // Continue with original file
      }
    }

    // Proceed with posting the message
    bool success = await postMessage(
      userId,
      content,
      mediaPath: effectiveMediaPath,
      mediaType: mediaType,
      familyId: familyId,
      // Pass the video data if available
      videoUrl: videoData?['videoUrl'],
      thumbnailUrl: videoData?['thumbnailUrl'],
    );

    return success;
  }

  // Modify postMessage to accept videoUrl and thumbnailUrl
  Future<bool> postMessage(
    int userId,
    String content, {
    String? mediaPath,
    String? mediaType,
    int? familyId,
    String? videoUrl,
    String? thumbnailUrl,
  }) async {
    try {
      debugPrint('Starting postMessage for userId: $userId');
      debugPrint('Content: "$content"');
      debugPrint('Media path: $mediaPath, media type: $mediaType');
      debugPrint('Video URL: $videoUrl, thumbnail URL: $thumbnailUrl');
      debugPrint('Explicit family ID provided: $familyId');

      // First get the user's active family if no explicit family ID is provided
      int? effectiveFamilyId = familyId;
      if (effectiveFamilyId == null) {
        debugPrint(
          'No explicit family ID provided, fetching user data to get active family',
        );
        final userData = await getUserById(userId);
        debugPrint('User data received: $userData');

        // Get the active family ID for the user
        effectiveFamilyId = userData['familyId'];
        debugPrint('Using family ID from user data: $effectiveFamilyId');

        if (effectiveFamilyId == null) {
          debugPrint('Error: User has no family ID');
          throw Exception(
            'You need to be part of a family to post messages. Please create or join a family first.',
          );
        }
      }

      debugPrint(
        'User belongs to family: $effectiveFamilyId, proceeding with message',
      );

      // Use the exact same endpoint format as the successful script
      final url = '$baseUrl/api/users/$userId/messages';
      debugPrint('Creating MultipartRequest for POST to $url');

      var request = http.MultipartRequest('POST', Uri.parse(url));

      if (_token != null) {
        debugPrint('Adding authorization token to request: $_token');
        request.headers['Authorization'] = 'Bearer $_token';
      } else {
        debugPrint('Warning: No token available for message posting');
        throw Exception('No authentication token available');
      }

      if (content.isNotEmpty) {
        debugPrint('Adding content field: $content');
        request.fields['content'] = content;
        // Add the family ID to the request explicitly - this is critical
        request.fields['familyId'] = effectiveFamilyId.toString();
        debugPrint('Adding familyId field: $effectiveFamilyId');
      } else {
        debugPrint('No content provided for message');
      }

      // Handle remote video URLs from backend processing
      if (videoUrl != null && videoUrl.startsWith('http')) {
        // Convert absolute URLs back to relative paths when sending to server
        String relativeVideoUrl = videoUrl;
        if (videoUrl.contains(baseUrl)) {
          relativeVideoUrl = videoUrl.substring(baseUrl.length);
        }

        debugPrint('Adding relative video URL to message: $relativeVideoUrl');
        request.fields['videoUrl'] = relativeVideoUrl;

        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
          String relativeThumbnailUrl = thumbnailUrl;
          if (thumbnailUrl.contains(baseUrl)) {
            relativeThumbnailUrl = thumbnailUrl.substring(baseUrl.length);
          }

          debugPrint(
            'Adding relative thumbnail URL to message: $relativeThumbnailUrl',
          );
          request.fields['thumbnailUrl'] = relativeThumbnailUrl;
        }

        // Set media type to video
        request.fields['mediaType'] = 'video';
      }
      // Handle media files
      else if (mediaPath != null && mediaType != null && !kIsWeb) {
        debugPrint('Adding media to message: $mediaPath, type: $mediaType');

        // Check if file exists
        final file = File(mediaPath);
        if (!await file.exists()) {
          debugPrint('Error: File does not exist at path: $mediaPath');
          throw Exception('File does not exist at path: $mediaPath');
        }

        // Check file size
        final fileSize = await file.length();
        final fileSizeMB = fileSize / (1024 * 1024);
        debugPrint('File size: $fileSize bytes ($fileSizeMB MB)');

        // Define size limits based on media type
        final double sizeLimit =
            mediaType == 'video' ? 20.0 : 5.0; // 20MB for video, 5MB for photos

        // Warn user if file is large (but still allow upload - server will handle it)
        if (fileSizeMB > sizeLimit) {
          debugPrint(
            'Warning: File size $fileSizeMB MB exceeds recommended limit of $sizeLimit MB',
          );
          // We'll still upload, the server will handle it as a large file
        }

        debugPrint('File exists, size: ${await file.length()} bytes');
        request.fields['mediaType'] = mediaType;

        try {
          debugPrint('Creating MultipartFile from path: $mediaPath');
          final mediaFile = await http.MultipartFile.fromPath(
            'media',
            mediaPath,
          );
          debugPrint(
            'Created MultipartFile: ${mediaFile.filename}, length: ${mediaFile.length}',
          );
          request.files.add(mediaFile);
          debugPrint('Media file added to request successfully');
        } catch (e) {
          debugPrint('Error adding media to request: $e');
          rethrow;
        }
      }

      debugPrint('Request headers: ${request.headers}');
      debugPrint('Request fields: ${request.fields}');
      if (request.files.isNotEmpty) {
        debugPrint('Request contains ${request.files.length} files');
        for (var file in request.files) {
          debugPrint(
            'File: ${file.field} - ${file.filename} (${file.length} bytes)',
          );
        }
      }

      debugPrint('Sending request...');
      final response = await request.send();
      debugPrint('Message post response status: ${response.statusCode}');
      final responseBody = await response.stream.bytesToString();
      debugPrint('Response body: $responseBody');

      if (response.statusCode != 201) {
        debugPrint('Error posting message: $responseBody');

        // Try to parse the error message if available
        String errorMessage = 'Failed to post message';
        if (responseBody.isNotEmpty) {
          try {
            final jsonResponse = jsonDecode(responseBody);
            debugPrint('Parsed error response: $jsonResponse');
            if (jsonResponse is Map && jsonResponse.containsKey('error')) {
              errorMessage = jsonResponse['error'];
            } else if (jsonResponse is String) {
              errorMessage = jsonResponse;
            }
          } catch (e) {
            debugPrint('Error parsing response body: $e');
          }
        }

        if (response.statusCode == 400) {
          errorMessage =
              'Bad request: $errorMessage (possibly image upload issue)';
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage = 'Authentication issue: $errorMessage';
        } else if (response.statusCode >= 500) {
          errorMessage = 'Server error: $errorMessage';
        }

        debugPrint('Throwing exception with message: $errorMessage');
        throw Exception('$errorMessage: $responseBody');
      } else {
        debugPrint('Message posted successfully: $responseBody');
        return true;
      }
    } catch (e) {
      debugPrint('Error posting message: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      debugPrint('Getting messages with token: $_token');
    } else {
      debugPrint('No token available for getting messages');
    }
    debugPrint('Getting messages for user $userId');

    final apiUrl = '$baseUrl/api/users/$userId/messages';
    debugPrint('API URL for messages: $apiUrl');

    final response = await client.get(Uri.parse(apiUrl), headers: headers);
    debugPrint(
      '🔍 GET MESSAGES RESPONSE: status=${response.statusCode}, body length=${response.body.length}',
    );

    // Print the first 500 characters of the response for debugging
    debugPrint(
      'First 500 chars of response: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
    );

    if (response.statusCode == 200) {
      try {
        List<dynamic> data = jsonDecode(response.body);
        debugPrint('✅ Successfully decoded JSON with ${data.length} messages');

        // IMPORTANT: Log ALL messages to verify what we're getting from the API
        debugPrint('=============== ALL MESSAGES FROM API ===============');
        for (int i = 0; i < data.length; i++) {
          final msg = data[i];
          debugPrint(
            '📄 Message $i - ID: ${msg['id']}, Content: ${msg['content']}',
          );

          // Log key fields that might cause issues
          final keys = msg.keys.toList();
          debugPrint('   Keys: ${keys.join(", ")}');
          debugPrint('   Timestamp: ${msg['timestamp']}');
          debugPrint('   FamilyId: ${msg['familyId']}');

          if (msg['mediaType'] != null) {
            debugPrint(
              '   Media: ${msg['mediaType']}, URL: ${msg['mediaUrl']}',
            );
            if (msg['thumbnailUrl'] != null) {
              debugPrint('   Thumbnail: ${msg['thumbnailUrl']}');
            } else {
              debugPrint('   ⚠️ No thumbnailUrl found for video message');
            }
          }

          // Add separators between messages for clarity
          debugPrint('   --------------------');
        }
        debugPrint('=============== END MESSAGES ===============');

        return List<Map<String, dynamic>>.from(data);
      } catch (e) {
        debugPrint('❌ ERROR PARSING MESSAGES JSON: $e');
        // Try to print more of the response to debug
        debugPrint('ERROR RESPONSE BODY: ${response.body}');
        throw Exception('Failed to parse messages: $e');
      }
    } else {
      debugPrint(
        '❌ Error getting messages: ${response.statusCode}, ${response.body}',
      );
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
  }

  Future<void> updatePhoto(int userId, String photoPath) async {
    if (kIsWeb) {
      // Web implementation will come in a separate update
      // For now, show a message that this functionality is coming soon
      debugPrint('Web file upload not fully implemented for updatePhoto');
      return; // Skip on web for now
    }

    debugPrint('Updating photo from path: $photoPath');

    try {
      // Check file size before uploading
      final file = File(photoPath);
      final fileSize = await file.length();
      final fileSizeKB = fileSize ~/ 1024;
      debugPrint('Photo file size: $fileSizeKB KB');

      if (fileSize > 1 * 1024 * 1024) {
        // 1MB limit
        throw Exception(
          'File size exceeds 1MB limit (${fileSizeKB}KB). Please select a smaller image.',
        );
      }

      // Create a multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users/$userId/update-photo'),
      );

      // Add authorization header if token exists
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }

      // Add the file to the request
      final photoFile = await http.MultipartFile.fromPath('photo', photoPath);
      request.files.add(photoFile);
      debugPrint('Adding file with length: ${photoFile.length} bytes');

      // Send the request
      debugPrint('Sending photo upload request to: ${request.url}');
      final streamedResponse = await request.send();

      // Get the response body
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('Upload photo response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');

      // Try to parse the response body, but handle if it's empty
      String responseBody = 'Empty response';
      if (response.body.isNotEmpty) {
        responseBody = response.body;
        debugPrint('Response body: $responseBody');
        try {
          final jsonResponse = jsonDecode(responseBody);
          debugPrint('Parsed JSON response: $jsonResponse');
        } catch (e) {
          debugPrint('Not JSON response: $e');
        }
      }

      if (response.statusCode != 200) {
        if (response.statusCode == 413) {
          throw Exception(
            'File size too large for server. Please use a smaller image.',
          );
        }
        throw Exception(
          'Failed to update photo: status code ${response.statusCode}, ${response.reasonPhrase}, $responseBody',
        );
      }

      // Clear any cached photo data that might be in memory
      try {
        if (PaintingBinding.instance != null) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      } catch (e) {
        debugPrint('Error clearing image cache: $e');
        // Continue anyway since this is just a cleanup step
      }

      debugPrint('Photo updated successfully');
    } catch (e) {
      debugPrint('Error updating photo: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getFamilyMembers(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    debugPrint('ApiService: Getting family members for user $userId');
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/family-members'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      final members =
          (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      debugPrint('ApiService: Got ${members.length} family members');
      return members;
    } else if (response.statusCode == 400) {
      debugPrint('ApiService: Got 400 response from getFamilyMembers');
      return [];
    } else {
      debugPrint(
        'ApiService: Error ${response.statusCode} from getFamilyMembers: ${response.body}',
      );
      throw Exception('Failed to get family members: ${response.body}');
    }
  }

  // Get members of a specific family
  Future<List<Map<String, dynamic>>> getFamilyMembersByFamilyId(
    int userId,
    int familyId,
  ) async {
    debugPrint(
      'ApiService: Getting members for family $familyId (user $userId)',
    );

    // First try to get member preferences data
    final memberPreferences = await getMemberMessagePreferences(userId);

    // Filter to only include members of the specified family
    final familyMembers =
        memberPreferences.where((pref) {
          return pref['familyId'] == familyId;
        }).toList();

    // If we found members through preferences, return them
    if (familyMembers.isNotEmpty) {
      debugPrint(
        'ApiService: Found ${familyMembers.length} members in family $familyId from preferences',
      );
      return familyMembers;
    }

    // Otherwise, fall back to getting family members directly
    debugPrint(
      'ApiService: No member preferences found, falling back to family membership data',
    );

    try {
      // Get all family members
      final allMembers = await getFamilyMembers(userId);

      // Get family details to enhance the data
      Map<String, dynamic>? familyDetails;
      try {
        familyDetails = await getFamily(familyId);
      } catch (e) {
        debugPrint('ApiService: Failed to get family details: $e');
      }

      // Build member data in the same format as preferences would return
      List<Map<String, dynamic>> result = [];

      for (var member in allMembers) {
        // Only include members of this family
        if (member['familyId'] == familyId) {
          // Create a preference-like structure
          result.add({
            'familyId': familyId,
            'receiveMessages': true, // Default to true
            'memberUserId': member['userId'],
            'memberFirstName':
                member['firstName'] ?? member['memberFirstName'] ?? 'Unknown',
            'memberLastName':
                member['lastName'] ?? member['memberLastName'] ?? '',
            'memberUsername':
                member['username'] ?? member['memberUsername'] ?? 'No username',
            'isOwner':
                member['role'] == 'ADMIN' || member['role'] == 'FAMILY_ADMIN',
            'memberOfFamilyName': familyDetails?['name'] ?? 'Unknown Family',
            'userId': userId,
          });
        }
      }

      debugPrint(
        'ApiService: Created ${result.length} synthetic member records for family $familyId',
      );
      return result;
    } catch (e) {
      debugPrint('ApiService: Error in fallback member lookup: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getFamily(int familyId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    debugPrint('Getting family details for ID: $familyId');

    final response = await client.get(
      Uri.parse('$baseUrl/api/users/families/$familyId'),
      headers: headers,
    );

    debugPrint(
      'Get family response: statusCode=${response.statusCode}, body=${response.body}',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 404) {
      throw Exception('Family not found');
    } else {
      throw Exception('Failed to get family details: ${response.body}');
    }
  }

  Future<void> leaveFamily(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/leave-family'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to leave family: ${response.body}');
    }
  }

  Future<void> inviteUser(int userId, String email) async {
    if (_token == null) {
      throw Exception('No authentication token available');
    }
    try {
      debugPrint('Sending invitation from user ID: $userId to email: $email');

      // First get the family that this user owns
      final ownedFamily = await getOwnedFamily(userId);

      if (ownedFamily == null || ownedFamily['familyId'] == null) {
        throw 'You need to create a family before you can invite others. You can only invite to a family you own.';
      }

      final familyId = ownedFamily['familyId'];
      debugPrint('User is inviting to family ID: $familyId (owned by user)');

      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/invite'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'email': email, 'familyId': familyId}),
      );
      debugPrint(
        'Invite response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode != 200) {
        String errorMessage = 'Failed to send invitation';

        // Try to parse the error message from the response body
        try {
          final Map<String, dynamic> errorBody = jsonDecode(response.body);
          if (errorBody.containsKey('message')) {
            errorMessage = errorBody['message'];
          } else if (errorBody.containsKey('error')) {
            errorMessage = errorBody['error'];
          }
        } catch (e) {
          // If we can't parse the response body, use a generic message with status code
          errorMessage = 'Failed to send invitation: ${response.statusCode}';
        }

        // Handle specific error cases based on status code
        if (response.statusCode == 400) {
          // Bad request errors
          if (response.body.contains('already pending')) {
            errorMessage =
                'An invitation to this family is already pending for this email';
          } else if (response.body.contains('already in your family')) {
            errorMessage = 'This person is already in your family';
          } else if (response.body.contains('invalid email')) {
            errorMessage = 'The email address is invalid';
          }
        } else if (response.statusCode == 403) {
          errorMessage =
              'You do not have permission to send invitations to this family';
        } else if (response.statusCode == 404) {
          errorMessage = 'Family not found';
        } else if (response.statusCode == 500) {
          errorMessage = 'Server error occurred. Please try again later';
        }

        throw errorMessage;
      }
    } catch (e) {
      debugPrint('Error sending invitation: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getInvitations() async {
    if (_token == null) {
      debugPrint('No authentication token available');
      return [];
    }

    try {
      debugPrint('Fetching invitations');
      final response = await client.get(
        Uri.parse('$baseUrl/api/users/invitations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        'Get invitations response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final invitations = List<Map<String, dynamic>>.from(
          jsonDecode(response.body),
        );

        // Log each invitation for debugging
        for (var inv in invitations) {
          debugPrint(
            'Invitation: id=${inv['id']}, status=${inv['status']}, familyId=${inv['familyId']}',
          );
        }

        return invitations;
      } else {
        debugPrint(
          'Error fetching invitations: ${response.statusCode}, ${response.body}',
        );
        return []; // Return empty list for any error
      }
    } catch (e) {
      debugPrint('Error fetching invitations: $e');
      return []; // Return empty list for any error
    }
  }

  Future<Map<String, dynamic>> acceptInvitation(int invitationId) async {
    if (_token == null) {
      debugPrint('No authentication token available');
      return {'error': 'No authentication token available'};
    }

    try {
      debugPrint('Accepting invitation ID: $invitationId');
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/invitations/$invitationId/accept'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        'Accept invitation response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return {
          'error': 'Invitation not found',
          'message': 'The invitation may have expired or been cancelled',
        };
      } else {
        // Try to parse the error message from the response body
        String errorMessage = 'Failed to accept invitation';
        try {
          final Map<String, dynamic> errorBody = jsonDecode(response.body);
          if (errorBody.containsKey('message')) {
            errorMessage = errorBody['message'];
          } else if (errorBody.containsKey('error')) {
            errorMessage = errorBody['error'];
          }
        } catch (e) {
          // If we can't parse the response body, use a generic message
          errorMessage = 'Failed to accept invitation: ${response.statusCode}';
        }

        // Handle specific error cases
        if (response.statusCode == 400) {
          if (response.body.contains('already a member')) {
            errorMessage = 'You are already a member of this family';
          } else if (response.body.contains('expired')) {
            errorMessage = 'This invitation has expired';
          }
        } else if (response.statusCode == 403) {
          errorMessage = 'You do not have permission to accept this invitation';
        } else if (response.statusCode == 500) {
          errorMessage = 'Server error occurred. Please try again later';
        }

        debugPrint('Error accepting invitation: $errorMessage');
        return {'error': errorMessage};
      }
    } catch (e) {
      debugPrint('Error accepting invitation: $e');
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> rejectInvitation(int invitationId) async {
    if (_token == null) {
      debugPrint('No authentication token available');
      return {'error': 'No authentication token available'};
    }

    try {
      debugPrint('Rejecting invitation ID: $invitationId');
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/invitations/$invitationId/reject'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        'Reject invitation response: statusCode=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return {
          'error': 'Invitation not found',
          'message': 'The invitation may have expired or been cancelled',
        };
      } else {
        // Try to parse the error message from the response body
        String errorMessage = 'Failed to decline invitation';
        try {
          final Map<String, dynamic> errorBody = jsonDecode(response.body);
          if (errorBody.containsKey('message')) {
            errorMessage = errorBody['message'];
          } else if (errorBody.containsKey('error')) {
            errorMessage = errorBody['error'];
          }
        } catch (e) {
          // If we can't parse the response body, use a generic message
          errorMessage = 'Failed to decline invitation: ${response.statusCode}';
        }

        // Handle specific error cases
        if (response.statusCode == 400) {
          if (response.body.contains('expired')) {
            errorMessage = 'This invitation has expired';
          }
        } else if (response.statusCode == 403) {
          errorMessage =
              'You do not have permission to decline this invitation';
        } else if (response.statusCode == 500) {
          errorMessage = 'Server error occurred. Please try again later';
        }

        debugPrint('Error rejecting invitation: $errorMessage');
        return {'error': errorMessage};
      }
    } catch (e) {
      debugPrint('Error rejecting invitation: $e');
      return {'error': e.toString()};
    }
  }

  /// Get all families a user belongs to, including both owned and joined families.
  /// Returns a list of family objects with membership details
  Future<List<Map<String, dynamic>>> getUserFamilies(int userId) async {
    debugPrint('getUserFamilies: Getting families for user ID: $userId');
    final token = await getToken();
    if (token == null) {
      throw Exception('No token available');
    }

    try {
      debugPrint('Sending request to $baseUrl/api/users/$userId/families');
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId/families'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        debugPrint(
          'Get families response: statusCode=${response.statusCode}, body=${response.body}',
        );
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((family) => family as Map<String, dynamic>).toList();
      } else {
        debugPrint(
          'Error getting families: ${response.statusCode} ${response.body}',
        );
        throw Exception('Failed to get families: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting families: $e');
      throw Exception('Error getting families: $e');
    }
  }

  /// Get family a user owns (created), if any
  Future<Map<String, dynamic>?> getOwnedFamily(int userId) async {
    final families = await getUserFamilies(userId);
    final ownedFamily = families.firstWhere(
      (family) => family['role'] == 'ADMIN' || family['isOwner'] == true,
      orElse: () => <String, dynamic>{},
    );

    return ownedFamily.isEmpty ? null : ownedFamily;
  }

  /// Get families user has joined but doesn't own
  Future<List<Map<String, dynamic>>> getJoinedFamilies(int userId) async {
    final families = await getUserFamilies(userId);
    return families
        .where(
          (family) => family['role'] != 'ADMIN' && family['isOwner'] != true,
        )
        .toList();
  }

  /// Set the active family for a user (the family that will receive messages by default)
  Future<void> setActiveFamily(int userId, int familyId) async {
    final token = await getToken();
    if (token == null) {
      throw Exception('No token available');
    }

    try {
      debugPrint('Setting active family $familyId for user $userId');
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/$userId/set-active-family/$familyId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Error setting active family: ${response.statusCode} ${response.body}',
        );
        throw Exception('Failed to set active family: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error setting active family: $e');
      throw Exception('Error setting active family: $e');
    }
  }

  /// Get the active family for a user
  Future<Map<String, dynamic>?> getActiveFamily(int userId) async {
    final token = await getToken();
    if (token == null) {
      throw Exception('No token available');
    }

    try {
      debugPrint('Getting active family for user $userId');
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId/active-family'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 404) {
        // No active family found
        return null;
      } else {
        throw Exception('Failed to get active family: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting active family: $e');
      throw Exception('Error getting active family: $e');
    }
  }

  // Get invitations for a specific user
  Future<List<Map<String, dynamic>>> getFamilyInvitationsForUser(
    int userId,
  ) async {
    // This is essentially a wrapper for getInvitations()
    return getInvitations();
  }

  // Respond to a family invitation (accept or decline)
  Future<Map<String, dynamic>> respondToFamilyInvitation(
    int invitationId,
    bool accept,
  ) async {
    // Call the appropriate method based on whether to accept or decline
    if (accept) {
      return acceptInvitation(invitationId);
    } else {
      return rejectInvitation(invitationId);
    }
  }

  // Invite a user to the family by email - this is an alias for inviteUser for backward compatibility
  Future<void> inviteUserToFamily(int userId, String email) async {
    return inviteUser(userId, email);
  }

  // Returns true if a token is available and presumably valid
  bool hasValidToken() {
    return _token != null && _token!.isNotEmpty;
  }

  // Get the stored token for external use
  Future<String?> getToken() async {
    if (_token == null) {
      await _loadToken();
    }
    return _token;
  }

  /// Special method for web browser photo uploads
  /// This is separate from the mobile version since file handling is different
  Future<void> updatePhotoWeb(
    int userId,
    List<int> bytes,
    String fileName,
  ) async {
    if (!kIsWeb) {
      throw Exception('This method is only for web browsers');
    }

    debugPrint(
      'Updating photo from web browser, fileSize: ${bytes.length} bytes',
    );

    try {
      // Check file size client-side
      final fileSizeKB = bytes.length ~/ 1024;
      if (bytes.length > 1 * 1024 * 1024) {
        // 1MB limit
        throw Exception(
          'File size exceeds 1MB limit (${fileSizeKB}KB). Please select a smaller image.',
        );
      }

      // For web, we create a request with the bytes directly
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users/$userId/update-photo'),
      );

      // Add authorization header if token exists
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }

      // Create a MultipartFile from bytes for web
      final multipartFile = http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: fileName,
      );
      request.files.add(multipartFile);
      debugPrint(
        'Adding web file with length: ${bytes.length} bytes, filename: $fileName',
      );

      // Send the request
      debugPrint('Sending web photo upload request to: ${request.url}');
      final streamedResponse = await request.send();

      // Get the response
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('Web upload photo response status: ${response.statusCode}');

      // Handle the response
      if (response.statusCode != 200) {
        if (response.statusCode == 413) {
          throw Exception(
            'File size too large for server. Please use a smaller image.',
          );
        }
        throw Exception(
          'Failed to update photo: status code ${response.statusCode}',
        );
      }

      // Clear image cache
      try {
        if (PaintingBinding.instance != null) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      } catch (e) {
        debugPrint('Error clearing image cache: $e');
      }

      debugPrint('Web photo uploaded successfully');
    } catch (e) {
      debugPrint('Error updating photo from web: $e');
      rethrow;
    }
  }

  // Update family details (name, etc.)
  Future<Map<String, dynamic>> updateFamilyDetails(
    int familyId,
    String familyName,
  ) async {
    debugPrint('Updating family $familyId with name: $familyName');

    try {
      final url = Uri.parse('$baseUrl/api/users/families/$familyId/update');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({'name': familyName}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Family updated successfully: $data');
        return data;
      } else {
        final errorBody = response.body;
        debugPrint(
          'Error updating family: statusCode=${response.statusCode}, body=$errorBody',
        );
        throw Exception('Failed to update family: $errorBody');
      }
    } catch (e) {
      debugPrint('Error updating family: $e');
      rethrow;
    }
  }

  // Get message preferences for a user
  Future<List<Map<String, dynamic>>> getMessagePreferences(int userId) async {
    debugPrint('Getting message preferences for user ID: $userId');

    try {
      final url = Uri.parse('$baseUrl/api/message-preferences/$userId');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        debugPrint('Successfully retrieved ${data.length} message preferences');
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        final errorBody = response.body;
        debugPrint(
          'Error getting message preferences: statusCode=${response.statusCode}, body=$errorBody',
        );
        throw Exception('Failed to get message preferences: $errorBody');
      }
    } catch (e) {
      debugPrint('Error getting message preferences: $e');
      rethrow;
    }
  }

  // Update message preference for a specific family
  Future<Map<String, dynamic>> updateMessagePreference(
    int userId,
    int familyId,
    bool receiveMessages,
  ) async {
    debugPrint(
      'Updating message preference for user $userId, family $familyId: receive=$receiveMessages',
    );

    try {
      final url = Uri.parse('$baseUrl/api/message-preferences/$userId/update');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final body = jsonEncode({
        'familyId': familyId,
        'receiveMessages': receiveMessages,
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Successfully updated message preference: $data');
        return data as Map<String, dynamic>;
      } else {
        final errorBody = response.body;
        debugPrint(
          'Error updating message preference: statusCode=${response.statusCode}, body=$errorBody',
        );
        throw Exception('Failed to update message preference: $errorBody');
      }
    } catch (e) {
      debugPrint('Error updating message preference: $e');
      rethrow;
    }
  }

  // Get member-level message preferences for a user
  Future<List<Map<String, dynamic>>> getMemberMessagePreferences(
    int userId,
  ) async {
    debugPrint('Getting member-level message preferences for user ID: $userId');

    try {
      final url = Uri.parse('$baseUrl/api/member-message-preferences/$userId');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      debugPrint('Requesting member message preferences from URL: $url');
      final response = await http.get(url, headers: headers);
      debugPrint(
        'Response status: ${response.statusCode}, response body: ${response.body}',
      );

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          debugPrint('Response body is empty, returning empty list');
          return [];
        }

        final List<dynamic> data = jsonDecode(response.body);
        debugPrint(
          'Successfully retrieved ${data.length} member message preferences',
        );
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else if (response.statusCode == 404) {
        // API endpoint might not exist yet, return empty list
        debugPrint(
          'Member message preferences endpoint not found (404) - returning empty list',
        );
        return [];
      } else {
        final errorBody = response.body;
        debugPrint(
          'Error getting member message preferences: statusCode=${response.statusCode}, body=$errorBody',
        );
        throw Exception('Failed to get member message preferences: $errorBody');
      }
    } catch (e) {
      debugPrint('Error getting member message preferences: $e');
      // Return empty list for now until backend implements this
      return [];
    }
  }

  // Update message preference for a specific family member
  Future<Map<String, dynamic>> updateMemberMessagePreference(
    int userId,
    int familyId,
    int? memberUserId,
    bool receiveMessages,
  ) async {
    // Validate member ID
    if (memberUserId == null) {
      debugPrint('Cannot update preference for null member ID');
      return {'success': false, 'message': 'Invalid member ID'};
    }

    debugPrint(
      'Updating member message preference for user $userId, family $familyId, member $memberUserId: receive=$receiveMessages',
    );

    try {
      final url = Uri.parse(
        '$baseUrl/api/member-message-preferences/$userId/update',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final body = jsonEncode({
        'familyId': familyId,
        'memberUserId': memberUserId,
        'receiveMessages': receiveMessages,
      });

      debugPrint('Sending request to URL: $url with body: $body');
      final response = await http.post(url, headers: headers, body: body);
      debugPrint(
        'Response status: ${response.statusCode}, body: ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Successfully updated member message preference: $data');
        return data as Map<String, dynamic>;
      } else {
        final errorBody = response.body;
        debugPrint(
          'Error updating member message preference: statusCode=${response.statusCode}, body=$errorBody',
        );
        throw Exception(
          'Failed to update member message preference: $errorBody',
        );
      }
    } catch (e) {
      debugPrint('Error updating member message preference: $e');
      rethrow;
    }
  }

  // SOCIAL ENGAGEMENT API METHODS

  // REACTIONS

  // Get reactions for a message
  Future<Map<String, dynamic>> getMessageReactions(int? messageId) async {
    if (messageId == null) {
      debugPrint('Error: Cannot get message reactions - Message ID is null');
      return {'reactions': [], 'counts': {}};
    }

    debugPrint('Getting reactions for message $messageId');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/reactions');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Get reactions response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get reactions: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting reactions: $e');
      return {'reactions': [], 'counts': {}};
    }
  }

  // Add a reaction to a message
  Future<Map<String, dynamic>> addReaction(
    int? messageId,
    String reactionType,
  ) async {
    if (messageId == null) {
      debugPrint('Error: Cannot add reaction - Message ID is null');
      return {'error': 'Message ID is null'};
    }

    debugPrint('Adding $reactionType reaction to message $messageId');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/reactions');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };
      final body = jsonEncode({'reactionType': reactionType});

      final response = await http.post(url, headers: headers, body: body);
      debugPrint(
        'Add reaction response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to add reaction: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error adding reaction: $e');
      return {'error': e.toString()};
    }
  }

  // Remove a reaction from a message
  Future<bool> removeReaction(int? messageId, String reactionType) async {
    if (messageId == null) {
      debugPrint('Error: Cannot remove reaction - Message ID is null');
      return false;
    }

    debugPrint('Removing $reactionType reaction from message $messageId');

    try {
      final url = Uri.parse(
        '$baseUrl/api/messages/$messageId/reactions/$reactionType',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.delete(url, headers: headers);
      debugPrint(
        'Remove reaction response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Failed to remove reaction: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error removing reaction: $e');
      return false;
    }
  }

  // COMMENTS

  // Get comments for a message
  Future<Map<String, dynamic>> getMessageComments(
    int? messageId, {
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String sortDir = 'desc',
  }) async {
    if (messageId == null) {
      debugPrint('Error: Cannot get message comments - Message ID is null');
      return {'comments': [], 'totalItems': 0};
    }

    debugPrint('Getting comments for message $messageId');

    try {
      final url = Uri.parse(
        '$baseUrl/api/messages/$messageId/comments?page=$page&size=$size&sortBy=$sortBy&sortDir=$sortDir',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Get comments response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get comments: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting comments: $e');
      return {'comments': [], 'totalItems': 0};
    }
  }

  // Get replies for a comment
  Future<Map<String, dynamic>> getCommentReplies(int commentId) async {
    debugPrint('Getting replies for comment $commentId');

    try {
      final url = Uri.parse(
        '$baseUrl/api/messages/comments/$commentId/replies',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Get comment replies response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get comment replies: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting comment replies: $e');
      rethrow;
    }
  }

  // Add a comment to a message
  Future<Map<String, dynamic>> addComment(
    int? messageId,
    String content, {
    int? parentCommentId,
  }) async {
    if (messageId == null) {
      debugPrint('Error: Cannot add comment - Message ID is null');
      return {'error': 'Message ID is null'};
    }

    debugPrint('Adding comment to message $messageId');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/comments');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final Map<String, dynamic> requestBody = {'content': content};

      if (parentCommentId != null) {
        requestBody['parentCommentId'] = parentCommentId;
      }

      final body = jsonEncode(requestBody);

      final response = await http.post(url, headers: headers, body: body);
      debugPrint(
        'Add comment response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to add comment: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error adding comment: $e');
      return {'error': e.toString()};
    }
  }

  // Update a comment
  Future<Map<String, dynamic>> updateComment(
    int commentId,
    String content,
  ) async {
    debugPrint('Updating comment $commentId: $content');

    try {
      final url = Uri.parse('$baseUrl/api/messages/comments/$commentId');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };
      final body = jsonEncode({'content': content});

      final response = await http.put(url, headers: headers, body: body);
      debugPrint(
        'Update comment response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to update comment: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error updating comment: $e');
      rethrow;
    }
  }

  // Delete a comment
  Future<bool> deleteComment(int commentId) async {
    debugPrint('Deleting comment $commentId');

    try {
      final url = Uri.parse('$baseUrl/api/messages/comments/$commentId');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.delete(url, headers: headers);
      debugPrint(
        'Delete comment response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Failed to delete comment: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      rethrow;
    }
  }

  // VIEWS

  // Mark a message as viewed
  Future<Map<String, dynamic>> markMessageAsViewed(int? messageId) async {
    if (messageId == null) {
      debugPrint('Error: Cannot mark message as viewed - Message ID is null');
      return {'error': 'Message ID is null'};
    }

    debugPrint('Marking message $messageId as viewed');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/views');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.post(url, headers: headers);
      debugPrint(
        'Mark message as viewed response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to mark message as viewed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error marking message as viewed: $e');
      return {'error': e.toString()};
    }
  }

  // Get message views
  Future<Map<String, dynamic>> getMessageViews(int? messageId) async {
    if (messageId == null) {
      debugPrint('Error: Cannot get message views - Message ID is null');
      return {'error': 'Message ID is null'};
    }

    debugPrint('Getting views for message $messageId');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/views');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Get message views response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get message views: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting message views: $e');
      return {'error': e.toString()};
    }
  }

  // Check if a message is viewed by the current user
  Future<bool> isMessageViewed(int? messageId) async {
    if (messageId == null) {
      debugPrint(
        'Error: Cannot check if message is viewed - Message ID is null',
      );
      return false;
    }

    debugPrint('Checking if message $messageId is viewed');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/views/check');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Check message viewed response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['viewed'] as bool;
      } else {
        throw Exception(
          'Failed to check if message is viewed: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error checking if message is viewed: $e');
      return false;
    }
  }

  // Get all engagement data for a message
  Future<Map<String, dynamic>> getMessageEngagementData(int messageId) async {
    debugPrint('Getting engagement data for message $messageId');

    try {
      final url = Uri.parse('$baseUrl/api/messages/$messageId/engagement');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Get engagement data response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get engagement data: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting engagement data: $e');
      rethrow;
    }
  }

  // Get engagement data for multiple messages at once (much more efficient)
  Future<Map<String, dynamic>> getBatchMessageEngagementData(
    List<int> messageIds,
  ) async {
    if (messageIds.isEmpty) {
      debugPrint(
        'Error: Cannot fetch batch engagement data - No message IDs provided',
      );
      return {'messages': {}};
    }

    // Limit batch size to prevent excessive payloads
    final ids = messageIds.take(50).toList();

    debugPrint('Getting batch engagement data for ${ids.length} messages');

    try {
      // Build query params with multiple messageIds
      final queryParams = ids.map((id) => 'messageIds=$id').join('&');
      final url = Uri.parse(
        '$baseUrl/api/messages/batch-engagement?$queryParams',
      );

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await http.get(url, headers: headers);
      debugPrint(
        'Batch engagement data response: status=${response.statusCode}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('Error response: ${response.body}');
        throw Exception(
          'Failed to get batch engagement data: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error getting batch engagement data: $e');
      return {'messages': {}};
    }
  }

  // Debug method to test thumbnail accessibility
  Future<bool> testThumbnailAccess(String thumbnailUrl) async {
    // If URL doesn't start with http, add the base URL
    final String fullUrl =
        thumbnailUrl.startsWith('http')
            ? thumbnailUrl
            : '$baseUrl$thumbnailUrl';

    debugPrint('🧪 Testing thumbnail URL accessibility: $fullUrl');

    try {
      final response = await client.get(Uri.parse(fullUrl));
      final isSuccess = response.statusCode == 200;

      debugPrint(
        '🔍 Thumbnail test result for $fullUrl: ${response.statusCode}',
      );
      debugPrint('  Content-Type: ${response.headers['content-type']}');
      debugPrint('  Content Length: ${response.contentLength} bytes');
      debugPrint('  Success: $isSuccess');

      return isSuccess;
    } catch (e) {
      debugPrint('⚠️ Error testing thumbnail URL: $e');
      return false;
    }
  }

  // Get all possible variants of a thumbnail URL to test
  List<String> getThumbnailUrlVariants(String originalPath) {
    final List<String> variants = [];

    // If it's already a full URL, add it as is
    if (originalPath.startsWith('http')) {
      variants.add(originalPath);
    }

    // Extract just the filename
    String filename = originalPath;
    if (originalPath.contains('/')) {
      filename = originalPath.substring(originalPath.lastIndexOf('/') + 1);
    }

    // Add variants with different paths
    variants.add('$baseUrl/uploads/thumbnails/$filename');
    variants.add('$baseUrl/public/media/thumbnails/$filename');
    variants.add('/uploads/thumbnails/$filename');
    variants.add('/public/media/thumbnails/$filename');

    return variants;
  }

  // Test all possible thumbnail URL variants and return the first working one
  Future<String?> findWorkingThumbnailUrl(String originalPath) async {
    debugPrint('🔎 Finding working thumbnail URL for: $originalPath');

    final variants = getThumbnailUrlVariants(originalPath);

    for (final variant in variants) {
      debugPrint('  Testing variant: $variant');
      if (await testThumbnailAccess(variant)) {
        debugPrint('✅ Found working thumbnail URL: $variant');
        return variant;
      }
    }

    debugPrint('❌ No working thumbnail URL found');
    return null;
  }

  // getTestToken101 method has been removed as it's no longer used

  // Helper method to make HTTP requests with automatic fallback to alternative servers
  Future<http.Response> _makeRequest(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
    int maxRetries = 2,
  }) async {
    headers = headers ?? {};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    // Start with current server
    String currentUrl = currentServerUrl;

    // Try up to maxRetries times
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final Uri uri = Uri.parse('$currentUrl$endpoint');
        debugPrint('📤 Attempt ${attempt + 1}/$maxRetries: $method $uri');

        http.Response response;

        switch (method.toUpperCase()) {
          case 'GET':
            response = await client
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 10));
            break;
          case 'POST':
            response = await client
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 15));
            break;
          case 'PUT':
            response = await client
                .put(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 15));
            break;
          case 'DELETE':
            response = await client
                .delete(uri, headers: headers)
                .timeout(const Duration(seconds: 10));
            break;
          default:
            throw Exception('Unsupported HTTP method: $method');
        }

        // Return successful response
        return response;
      } catch (e) {
        debugPrint('❌ Request failed: $e');

        // If we have retries left, try the next server
        if (attempt < maxRetries && await tryNextServer()) {
          currentUrl = currentServerUrl;
          debugPrint('🔄 Retrying with fallback server: $currentUrl');
          continue;
        }

        // No more retries or servers, rethrow the error
        rethrow;
      }
    }

    // Should never get here due to rethrow above, but needed to satisfy the compiler
    throw Exception('Failed to make request after $maxRetries retries');
  }
}
