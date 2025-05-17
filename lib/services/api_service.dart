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
import 'package:http_parser/http_parser.dart'; // For MediaType

class ApiService {
  // Dynamic baseUrl based on AppConfig
  String get baseUrl {
    final url = AppConfig().baseUrl;
    debugPrint("Using API base URL: $url");
    return url;
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
      debugPrint('''
❌ Connection test failed with error: $e
Network connection error. Please check:
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

  Future<void> testConnection() async {
    debugPrint('Testing connection to $baseUrl');
    try {
      final stopwatch = Stopwatch()..start();
      final response = await client
          .get(
            Uri.parse('$baseUrl/api/users/test'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      stopwatch.stop();
      debugPrint(
        'Connection test completed in ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ Connection test successful!');
      } else {
        debugPrint(
          '❌ Connection test failed with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('❌ Connection test failed with error: $e');
      debugPrint('''
Network connection error. Please check:
1. Is the backend server running? ($baseUrl/api/users/test)
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

      // No need to call commit - it's done automatically in the newer SharedPreferences API
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

      // Explicitly clear all cache that might cause auto-login
      await prefs.clear(); // This clears ALL shared preferences

      _token = null;
      debugPrint('Cleared all auth data from storage');
    } catch (e) {
      debugPrint('Error clearing token: $e');
    }
  }

  // Helper method to safely parse user ID from string with optional default value
  int? _safeParseId(String? idStr, {int? defaultValue}) {
    debugPrint(
      '🔍 Attempting to parse user ID from: "$idStr", default: $defaultValue',
    );
    if (idStr == null || idStr.isEmpty) {
      debugPrint(
        '⚠️ User ID string is null or empty, using default: $defaultValue',
      );
      return defaultValue;
    }
    try {
      final parsedId = int.parse(idStr);
      debugPrint('✅ Successfully parsed user ID: $parsedId');
      return parsedId;
    } catch (e) {
      debugPrint('❌ Error parsing user ID: $e, using default: $defaultValue');
      return defaultValue;
    }
  }

  /// Logout the current user and clear all session data
  Future<void> logout() async {
    debugPrint('Logging out user...');

    try {
      // Clear token and all session data
      await _clearToken();

      // Also ensure we set the explicitly_logged_out flag to prevent auto-login in debug mode
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('explicitly_logged_out', true);

      debugPrint('✅ User successfully logged out');
    } catch (e) {
      debugPrint('❌ Error during logout: $e');
      // Try again with direct SharedPreferences clearing
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        _token = null;
        debugPrint('✅ User logged out through fallback method');
      } catch (secondError) {
        debugPrint('❌ Fatal error during logout fallback: $secondError');
      }
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
      debugPrint('Attempting login for email: $email');

      // Check if we already have shared preferences available
      final prefs = await SharedPreferences.getInstance();
      final prefsKeys = prefs.getKeys();
      debugPrint('SharedPreferences before login: $prefsKeys');

      // Clear any existing tokens to start fresh
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');
      await prefs.remove('token_save_time');

      final response = await http.post(
        Uri.parse('$baseUrl/api/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        debugPrint('Login successful, parsing response');
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
                await prefs.setString('user_id', userIdStr);

                // Verify user_id was actually saved
                final storedUserId = prefs.getString('user_id');
                if (storedUserId != userIdStr) {
                  debugPrint(
                    '⚠️ CRITICAL: user_id verification failed! Retrying...',
                  );
                  // Try one more time with forced persistance
                  await prefs.setString('user_id', userIdStr);
                }

                debugPrint(
                  '💾 Stored user_id in SharedPreferences: ${data['userId']}',
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

              // Clear the explicitly_logged_out flag
              await prefs.setBool('explicitly_logged_out', false);

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
                await prefs.setString('user_id', userIdStr);

                // Verify user_id was actually saved
                final storedUserId = prefs.getString('user_id');
                if (storedUserId != userIdStr) {
                  debugPrint(
                    '⚠️ CRITICAL: user_id verification failed! Retrying...',
                  );
                  // Try one more time with forced persistance
                  await prefs.setString('user_id', userIdStr);
                }

                debugPrint(
                  '💾 Stored user_id in SharedPreferences: ${data['userId']}',
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

              // Clear the explicitly_logged_out flag
              await prefs.setBool('explicitly_logged_out', false);
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

      // Check if user explicitly logged out - prevent debug auto-login if true
      final wasExplicitlyLoggedOut =
          prefs.getBool('explicitly_logged_out') ?? false;
      if (wasExplicitlyLoggedOut) {
        debugPrint(
          'User explicitly logged out, preventing auto-login even in debug mode',
        );

        // In debug mode, we need to be extra cautious
        if (kDebugMode) {
          // Make doubly sure we're not auto-logging in
          await _clearToken();
          await prefs.setBool('is_logged_in', false);
          debugPrint('DEBUG MODE: Enforcing logged out state');
        }
        return null;
      }

      // CRITICAL FIX: Check for user_id persistence issues
      final allKeys = prefs.getKeys();
      debugPrint('📋 SHARED PREFERENCES CURRENT STATE:');
      debugPrint('All keys: $allKeys');

      // Check for is_logged_in flag FIRST - this is the primary indicator
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      // If user is not logged in according to flag, return null immediately
      // This prevents debug mode from auto-setting user 101
      if (!isLoggedIn && !kDebugMode) {
        debugPrint('⚠️ Not logged in according to is_logged_in flag');
        await _clearToken(); // Ensure all auth data is cleared
        return null;
      }

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

          // Do not set any user ID in debug mode
          if (kDebugMode && isLoggedIn) {
            debugPrint('Debug mode detected, but not auto-setting any user ID');
          }
        }
      } else {
        debugPrint('⚠️ user_id KEY NOT FOUND in SharedPreferences!');

        // Do not auto-set any user ID
        if (kDebugMode && isLoggedIn) {
          debugPrint('Debug mode detected, but not auto-setting any user ID');
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

        // Don't use hardcoded fallback ID
        final userId = _safeParseId(validUserIdStr);

        // In debug mode, we'll accept missing login status only if explicitly set
        final effectiveIsLoggedIn =
            kDebugMode && isLoggedIn ? true : isLoggedIn;

        if (effectiveIsLoggedIn && userId != null) {
          debugPrint(
            '🔄 Found backup login info, attempting to restore session',
          );

          // For development builds with valid ID
          if (kDebugMode && isLoggedIn) {
            debugPrint('🔑 Using stored credentials in debug mode');
            // Skip token checks in debug mode but only if we have a valid ID
            if (userId != null) {
              return {'userId': userId, 'role': userRole ?? 'USER'};
            } else {
              debugPrint('No valid user ID found, need to log in again');
              return null;
            }
          }

          // Return the user info from backup
          debugPrint('🔄 Returning user data from backup login info');
          return {'userId': userId, 'role': userRole ?? 'USER'};
        }

        debugPrint('No backup login info available');
        return null;
      }

      // Try to validate token with the server
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };
      final currentUserPath = _getApiEndpoint('/api/users/current');
      debugPrint(
        'Sending request to $baseUrl$currentUserPath with token: ${_token!.substring(0, Math.min(10, _token!.length))}...',
      );
      final response = await client.get(
        Uri.parse('$baseUrl$currentUserPath'),
        headers: headers,
      );
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

        // Safer handling of possibly null userId
        int? userId;
        if (responseBody['userId'] == null) {
          // Use the value from SharedPreferences without hardcoded fallback
          userId = _safeParseId(prefs.getString('user_id'));
          if (userId == null) {
            debugPrint('⚠️ No valid user ID available, need to log in again');
            return null;
          }
          debugPrint(
            '⚠️ Using fallback userId from SharedPreferences: $userId',
          );
        } else {
          // Try to convert to int safely
          try {
            userId = (responseBody['userId'] as num).toInt();
          } catch (e) {
            // If conversion fails, try to parse without hardcoded fallback
            userId = int.tryParse(responseBody['userId'].toString());
            if (userId == null) {
              debugPrint('⚠️ Failed to parse user ID, need to log in again');
              return null;
            }
            debugPrint('⚠️ Fallback conversion of userId: $userId');
          }
        }

        // Final null check before returning
        if (userId == null) {
          debugPrint('⚠️ User ID is null, cannot proceed with authentication');
          return null;
        }

        return {
          'userId': userId,
          'role': responseBody['role'] as String? ?? 'USER',
        };
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

        // Don't use hardcoded fallback ID
        final userId = _safeParseId(validUserIdStr);

        // In debug mode, we'll accept missing login status only if explicitly set
        final effectiveIsLoggedIn =
            kDebugMode && isLoggedIn ? true : isLoggedIn;

        if (effectiveIsLoggedIn && userId != null) {
          debugPrint(
            '🔄 Found backup login info, attempting to restore session',
          );

          // For development builds with valid ID
          if (kDebugMode && isLoggedIn) {
            debugPrint('🔑 Using stored credentials in debug mode');
            // Skip token checks in debug mode but only if we have a valid ID
            if (userId != null) {
              return {'userId': userId, 'role': userRole ?? 'USER'};
            } else {
              debugPrint('No valid user ID found, need to log in again');
              return null;
            }
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

      // Don't use hardcoded fallback ID
      final userId = _safeParseId(validUserIdStr);

      // In debug mode, we'll accept missing login status only if explicitly set
      final effectiveIsLoggedIn = kDebugMode && isLoggedIn ? true : isLoggedIn;

      if (effectiveIsLoggedIn && userId != null) {
        debugPrint('🔄 Found backup login info, attempting to restore session');

        // For development builds with valid ID
        if (kDebugMode && isLoggedIn) {
          debugPrint('🔑 Using stored credentials in debug mode');
          // Skip token checks in debug mode but only if we have a valid ID
          if (userId != null) {
            return {'userId': userId, 'role': userRole ?? 'USER'};
          } else {
            debugPrint('No valid user ID found, need to log in again');
            return null;
          }
        }
      }
    }
  }

  /// Register a new user
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
    try {
      debugPrint('Registering user with username: $username, email: $email');

      // Prepare the form data
      final Map<String, String> userData = {
        'username': username,
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'role': userRole,
      };

      // Convert to JSON
      final userDataJson = json.encode(userData);

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users'),
      );

      // Add JSON data part
      request.files.add(
        http.MultipartFile.fromString(
          'userData',
          userDataJson,
          contentType: MediaType('application', 'json'),
        ),
      );

      // Add photo if provided
      if (photoPath != null) {
        final file = File(photoPath);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath('photo', photoPath),
          );
        }
      }

      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        debugPrint('Registration successful: ${responseData['userId']}');
        return responseData;
      } else {
        debugPrint('Registration failed: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        throw Exception('Registration failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error during registration: $e');
      rethrow;
    }
  }

  // Get user data by ID
  Future<Map<String, dynamic>> getUserById(int id) async {
    final headers = {'Content-Type': 'application/json'};
    debugPrint('getUserById: Getting user with ID: $id');
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available, Authorization header not set');
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$id'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get user: ${response.body}');
    }
  }

  // Get messages for a user
  Future<List<Map<String, dynamic>>> getMessages(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    final apiUrl = '$baseUrl/api/users/$userId/messages';
    debugPrint('API URL for messages: $apiUrl');

    final response = await client.get(Uri.parse(apiUrl), headers: headers);

    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to get messages: ${response.body}');
    }
  }

  // Post a message
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
        debugPrint('Adding authorization token to request');
        request.headers['Authorization'] = 'Bearer $_token';
      } else {
        debugPrint('Warning: No token available for message posting');
        throw Exception('No authentication token available');
      }

      if (content.isNotEmpty) {
        debugPrint('Adding content field: $content');
        request.fields['content'] = content;
        // Add the family ID to the request explicitly
        request.fields['familyId'] = effectiveFamilyId.toString();
        debugPrint('Adding familyId field: $effectiveFamilyId');
      } else {
        debugPrint('No content provided for message');
      }

      // Handle remote video URLs from backend processing
      if (videoUrl != null && videoUrl.startsWith('http')) {
        debugPrint('Adding remote video URL to message: $videoUrl');
        request.fields['videoUrl'] = videoUrl;
      }

      if (thumbnailUrl != null && thumbnailUrl.startsWith('http')) {
        debugPrint('Adding thumbnail URL to message: $thumbnailUrl');
        request.fields['thumbnailUrl'] = thumbnailUrl;
      }

      // Add media file if provided
      if (mediaPath != null && mediaType != null && !kIsWeb) {
        debugPrint('Adding media file to request: $mediaPath');
        final file = File(mediaPath);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'media',
              file.path,
              contentType:
                  mediaType == 'image'
                      ? MediaType('image', 'jpeg')
                      : mediaType == 'video'
                      ? MediaType('video', 'mp4')
                      : MediaType('application', 'octet-stream'),
            ),
          );
          debugPrint('Media file added successfully');
          request.fields['mediaType'] = mediaType;
        } else {
          debugPrint('Warning: Media file does not exist: $mediaPath');
        }
      } else if (mediaPath != null && mediaType != null && kIsWeb) {
        // Web-specific handling for media uploads
        debugPrint('Web media upload not implemented yet');
      }

      debugPrint('Sending request...');
      final response = await request.send();
      final responseString = await response.stream.bytesToString();
      debugPrint(
        'Response: status=${response.statusCode}, body=$responseString',
      );

      if (response.statusCode == 201) {
        debugPrint('✅ Message posted successfully');
        return true;
      } else {
        debugPrint('❌ Failed to post message: $responseString');
        return false;
      }
    } catch (e) {
      debugPrint('Exception in postMessage: $e');
      return false;
    }
  }

  // Post message with video processing
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

  // Update user photo
  Future<void> updatePhoto(int userId, String photoPath) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/users/$userId/update-photo'),
    );
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.headers['Content-Type'] = 'multipart/form-data';

    final file = File(photoPath);
    request.files.add(await http.MultipartFile.fromPath('photo', file.path));

    var response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to update photo: ${response.reasonPhrase}');
    }
  }

  // Update user photo from web (bytes)
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

      // Send the request
      final streamedResponse = await request.send();

      // Get the response
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('Failed to update photo: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error updating photo from web: $e');
      rethrow;
    }
  }

  // Get family members
  Future<List<Map<String, dynamic>>> getFamilyMembers(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/family-members'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } else if (response.statusCode == 400) {
      return [];
    } else {
      throw Exception('Failed to get family members: ${response.body}');
    }
  }

  // Get family details
  Future<Map<String, dynamic>> getFamily(int familyId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/families/$familyId'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get family: ${response.body}');
    }
  }

  // Get family invitations for a user - uses the centralized invitations endpoint
  Future<List<Map<String, dynamic>>> getFamilyInvitationsForUser(
    int userId,
  ) async {
    debugPrint('Getting invitations for user $userId using central endpoint');

    // This uses the centralized /api/users/invitations endpoint that was verified to work
    return getInvitations();
  }

  // Respond to a family invitation
  Future<Map<String, dynamic>> respondToFamilyInvitation(
    int invitationId,
    bool accept,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    final response = await client.post(
      Uri.parse('$baseUrl/api/invitations/$invitationId/respond'),
      headers: headers,
      body: jsonEncode({'accept': accept}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to respond to invitation: ${response.body}');
    }
  }

  // Invite a user to a family
  Future<Map<String, dynamic>> inviteUser(int userId, String email) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    // First get the family that this user owns
    final ownedFamily = await getOwnedFamily(userId);

    if (ownedFamily == null || ownedFamily['familyId'] == null) {
      throw 'You need to create a family before you can invite others. You can only invite to a family you own.';
    }

    final familyId = ownedFamily['familyId'];

    final response = await client.post(
      Uri.parse('$baseUrl/api/families/$familyId/invite'),
      headers: headers,
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to invite user: ${response.body}');
    }
  }

  // Get family owned by a user
  Future<Map<String, dynamic>?> getOwnedFamily(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/owned-family'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 404) {
      return null; // User doesn't own a family
    } else {
      throw Exception('Failed to get owned family: ${response.body}');
    }
  }

  // Update user demographics
  Future<Map<String, dynamic>> updateDemographics(
    int userId,
    Map<String, dynamic> data,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/demographics'),
      headers: headers,
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to update demographics: ${response.body}');
    }
  }

  // Helper method to upload video with thumbnail generation
  Future<Map<String, String>> uploadVideoWithThumbnail(File videoFile) async {
    try {
      // A simple implementation - in a real app would use the VideoUploadService
      return {'videoUrl': '', 'thumbnailUrl': ''};
    } catch (e) {
      debugPrint('Error in uploadVideoWithThumbnail: $e');
      return {};
    }
  }

  // Get all invitations
  Future<List<Map<String, dynamic>>> getInvitations() async {
    debugPrint('Getting invitations from the correct backend endpoint');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting invitations');
      return [];
    }

    try {
      // The endpoint is in UserController at /api/users/invitations (verified with curl)
      final response = await client.get(
        Uri.parse('$baseUrl/api/users/invitations'),
        headers: headers,
      );

      debugPrint('Invitations response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      } else if (response.statusCode == 404) {
        // Endpoint might have moved or changed - log the issue but don't crash
        debugPrint('Invitations endpoint not found (404): ${response.body}');
        return [];
      } else {
        debugPrint('Failed to get invitations: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching invitations: $e');
      return [];
    }
  }

  // Create a new family
  Future<Map<String, dynamic>> createFamily(
    int userId,
    String familyName,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final response = await client.post(
      Uri.parse('$baseUrl/api/families'),
      headers: headers,
      body: jsonEncode({'userId': userId, 'name': familyName}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to create family: ${response.body}');
    }
  }

  // Leave a family
  Future<Map<String, dynamic>> leaveFamily(int userId) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/leave-family'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to leave family: ${response.body}');
    }
  }

  // Get joined families
  Future<List<Map<String, dynamic>>> getJoinedFamilies(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/families'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to get joined families: ${response.body}');
    }
  }

  // Update family details
  Future<Map<String, dynamic>> updateFamilyDetails(
    int familyId,
    String name,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final response = await client.put(
      Uri.parse('$baseUrl/api/families/$familyId'),
      headers: headers,
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to update family details: ${response.body}');
    }
  }

  // Get message preferences
  Future<List<Map<String, dynamic>>> getMessagePreferences(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/message-preferences'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } else if (response.statusCode == 404) {
      return [];
    } else {
      throw Exception('Failed to get message preferences: ${response.body}');
    }
  }

  // Get message preferences for family members
  Future<List<Map<String, dynamic>>> getMemberMessagePreferences(
    int userId,
  ) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/member-message-preferences'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } else if (response.statusCode == 404) {
      return [];
    } else {
      throw Exception(
        'Failed to get member message preferences: ${response.body}',
      );
    }
  }

  // Update message preference
  Future<Map<String, dynamic>> updateMessagePreference(
    int userId,
    int familyId,
    bool receiveMessages,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/message-preferences'),
      headers: headers,
      body: jsonEncode({
        'familyId': familyId,
        'receiveMessages': receiveMessages,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to update message preference: ${response.body}');
    }
  }

  // Update member message preference
  Future<Map<String, dynamic>> updateMemberMessagePreference(
    int userId,
    int familyId,
    int memberUserId,
    bool receiveMessages,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/member-message-preferences'),
      headers: headers,
      body: jsonEncode({
        'familyId': familyId,
        'memberUserId': memberUserId,
        'receiveMessages': receiveMessages,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update member message preference: ${response.body}',
      );
    }
  }

  // Get family members by family ID
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

  // Test if a thumbnail URL is accessible
  Future<bool> testThumbnailAccess(String url) async {
    try {
      if (url.isEmpty) return false;

      // Make sure the URL is valid with a host
      if (!url.startsWith('http')) {
        debugPrint('Invalid URL format (missing http/https): $url');
        return false;
      }

      // Validate URI before making the request
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        debugPrint('Invalid URL (no host): $url');
        return false;
      }

      debugPrint('Making HEAD request to: $url');
      final response = await client
          .head(uri, headers: {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 3));

      final success = response.statusCode >= 200 && response.statusCode < 300;
      debugPrint(
        'Thumbnail access test result for $url: $success (status: ${response.statusCode})',
      );
      return success;
    } catch (e) {
      debugPrint('Error testing thumbnail access for $url: $e');
      return false;
    }
  }

  // Find a working thumbnail URL by trying different variants
  Future<String?> findWorkingThumbnailUrl(String baseUrl) async {
    if (baseUrl.isEmpty) return null;

    debugPrint('Finding working thumbnail URL for: $baseUrl');

    // If the baseUrl is just a path without a host (starts with /), prepend the mediaBaseUrl
    String fullBaseUrl = baseUrl;
    if (baseUrl.startsWith('/')) {
      fullBaseUrl = '$mediaBaseUrl$baseUrl';
      debugPrint('URL appears to be a path only, adding host: $fullBaseUrl');
    }

    final urlVariants = [
      fullBaseUrl,
      baseUrl.startsWith('http')
          ? baseUrl.replaceFirst('/api/', '/')
          : '$mediaBaseUrl$baseUrl',
      '$mediaBaseUrl${baseUrl.substring(baseUrl.lastIndexOf('/'))}',
    ];

    debugPrint('Testing URL variants: $urlVariants');

    for (final url in urlVariants) {
      try {
        debugPrint('Testing thumbnail URL: $url');
        if (await testThumbnailAccess(url)) {
          debugPrint('Found working thumbnail URL: $url');
          return url;
        }
      } catch (e) {
        debugPrint('Error testing URL variant $url: $e');
      }
    }

    // If all else fails, just return the full URL with media base
    final fallbackUrl = '$mediaBaseUrl$baseUrl';
    debugPrint('No working URL found, returning fallback: $fallbackUrl');
    return fallbackUrl;
  }
}
