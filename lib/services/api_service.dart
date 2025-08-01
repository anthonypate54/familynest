import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io' show File;
import '../config/app_config.dart';
import 'dart:math' as math;
import 'package:http_parser/http_parser.dart'; // For MediaType
import '../models/message.dart'; // Add this import
import '../models/dm_conversation.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}

class InvitationException implements Exception {
  final String message;
  final bool? userExists;
  final List<String>? suggestedEmails;

  InvitationException(this.message, {this.userExists, this.suggestedEmails});
}

class ApiService {
  // Dynamic baseUrl based on AppConfig
  String get baseUrl {
    final url = AppConfig().baseUrl;
    return url;
  }

  // Add isLoggedIn getter
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  // Media base URL - may be different in production (e.g., CDN)
  String get mediaBaseUrl {
    final url = AppConfig().mediaBaseUrl;
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
    debugPrint('🔄 API: Starting initialization');
    await _loadToken();

    // Only validate token if we have one and haven't validated it recently
    if (_token != null && _token!.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final lastValidation = prefs.getString('last_token_validation');

      if (lastValidation == null) {
        debugPrint(
          '🔑 API: No previous token validation found, validating now',
        );
        try {
          final currentUser = await getCurrentUser();
          if (currentUser != null) {
            debugPrint('✅ API: Token validation successful');
            await prefs.setString(
              'last_token_validation',
              DateTime.now().toIso8601String(),
            );
            return;
          } else {
            debugPrint('⚠️ API: Token validation failed - invalid token');
            await _clearToken();
          }
        } catch (e) {
          debugPrint('❌ API: Token validation error: $e');
          await _clearToken();
        }
      } else {
        final lastValid = DateTime.parse(lastValidation);
        final timeSinceValidation = DateTime.now().difference(lastValid);

        if (timeSinceValidation < const Duration(minutes: 5)) {
          debugPrint(
            '⏱️ API: Using cached token validation (${timeSinceValidation.inMinutes} minutes old)',
          );
          return;
        } else {
          debugPrint('🔄 API: Token validation expired, revalidating');
          try {
            final currentUser = await getCurrentUser();
            if (currentUser != null) {
              debugPrint('✅ API: Token revalidation successful');
              await prefs.setString(
                'last_token_validation',
                DateTime.now().toIso8601String(),
              );
              return;
            } else {
              debugPrint('⚠️ API: Token revalidation failed - invalid token');
              await _clearToken();
            }
          } catch (e) {
            debugPrint('❌ API: Token revalidation error: $e');
            await _clearToken();
          }
        }
      }
    }

    // Test connection if no valid token was found
    try {
      await testConnection();
    } catch (e) {
      debugPrint('❌ API: Connection test failed: $e');
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
        throw Exception('Server responded with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Connection test failed with error: $e');

      // Provide more specific error messages based on exception type
      String errorMessage = 'Unknown error occurred';
      if (e.toString().contains('SocketException')) {
        errorMessage =
            'Network connection failed. Cannot reach server at $baseUrl';
        debugPrint(
          '💡 This could be because the server is not running or WiFi connection issues',
        );
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = 'Connection timed out when trying to reach $baseUrl';
        debugPrint('💡 The server might be slow or unresponsive');
      } else if (e.toString().contains('HttpException')) {
        errorMessage = 'Invalid HTTP response from $baseUrl';
      }

      debugPrint('''
Network connection error. Please check:
1. Is the backend server running? ($baseUrl/api/users/test)
2. Are you using the correct IP address?
   - Android Emulator: 10.0.2.2:8080
   - iOS Simulator: localhost:8080
   - Physical Device: Your computer's IP address (10.0.0.10 or 10.0.0.81)
3. Go to Profile > Server Configuration to set the correct server URL
4. For real Android devices, try: adb reverse tcp:8080 tcp:8080
5. Is your device connected to the same WiFi network as your computer?
''');
      throw Exception(errorMessage);
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
          'Loaded token from storage: ${_token!.substring(0, math.min(10, _token!.length))}...',
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
        'Saved token to storage: ${token.substring(0, math.min(10, token.length))}...',
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

      // Set logout flags first
      await prefs.setBool('explicitly_logged_out', true);
      await prefs.setBool('is_logged_in', false);

      // Clear token data
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');
      await prefs.remove('token_save_time');

      // Clear additional login data
      await prefs.remove('user_id');
      await prefs.remove('user_role');
      await prefs.remove('login_time');

      // DO NOT clear ALL shared preferences
      // await prefs.clear(); // This would clear app settings too

      _token = null;
      debugPrint('Cleared auth data from storage');
    } catch (e) {
      debugPrint('Error clearing token: $e');
    }
  }

  /// Logout the current user and clear all session data
  Future<void> logout() async {
    debugPrint('🚪 LOGOUT: Starting logout process...');

    try {
      // Clear token from memory
      _token = null;

      // Clear all auth-related data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Debug: Show what exists before clearing
      final beforeKeys = prefs.getKeys();
      debugPrint('🚪 LOGOUT: SharedPreferences before clearing: $beforeKeys');
      debugPrint('🚪 LOGOUT: user_id before = "${prefs.getString('user_id')}"');

      // Remove all authentication data
      debugPrint('🚪 LOGOUT: Removing auth_token...');
      await prefs.remove('auth_token');
      debugPrint('🚪 LOGOUT: Removing auth_token_backup...');
      await prefs.remove('auth_token_backup');
      debugPrint('🚪 LOGOUT: Removing user_id...');
      await prefs.remove('user_id');
      debugPrint('🚪 LOGOUT: Removing user_role...');
      await prefs.remove('user_role');
      debugPrint('🚪 LOGOUT: Removing is_logged_in...');
      await prefs.remove('is_logged_in');
      debugPrint('🚪 LOGOUT: Removing login_time...');
      await prefs.remove('login_time');

      // For backward compatibility, still set this flag
      debugPrint('🚪 LOGOUT: Setting explicitly_logged_out flag...');
      await prefs.setBool('explicitly_logged_out', true);

      // Debug: Verify what was actually removed
      final afterKeys = prefs.getKeys();
      debugPrint('🚪 LOGOUT: SharedPreferences after clearing: $afterKeys');
      debugPrint('🚪 LOGOUT: user_id after = "${prefs.getString('user_id')}"');
      debugPrint(
        '🚪 LOGOUT: auth_token exists after = ${prefs.containsKey('auth_token')}',
      );

      debugPrint(
        '✅ LOGOUT: User successfully logged out - all auth data cleared',
      );
    } catch (e) {
      debugPrint('❌ LOGOUT: Error during logout: $e');
      // Simple fallback in case of error
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        _token = null;
        debugPrint('✅ LOGOUT: User logged out through fallback method');
      } catch (secondError) {
        debugPrint('❌ LOGOUT: Fatal error during logout: $secondError');
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

  // Login method to authenticate a user
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      debugPrint('Attempting login for username: $username');

      // Get SharedPreferences instance
      final prefs = await SharedPreferences.getInstance();

      // Clear any existing auth data to start fresh
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');

      final response = await http.post(
        Uri.parse('$baseUrl/api/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        debugPrint('Login successful, parsing response');
        try {
          final data = json.decode(response.body);
          debugPrint('Login response: $data');

          if (data['token'] != null) {
            // Save token and user data to SharedPreferences
            final String token = data['token'];

            // Save token (and backup for redundancy)
            await prefs.setString('auth_token', token);
            await prefs.setString('auth_token_backup', token);

            // Store user ID for identification
            if (data['userId'] != null) {
              final userIdStr = data['userId'].toString();
              await prefs.setString('user_id', userIdStr);
              debugPrint(
                'Stored user_id in SharedPreferences: ${data['userId']}',
              );
            }

            // Store role and login time
            await prefs.setString('user_role', data['role'] ?? 'USER');
            await prefs.setBool('is_logged_in', true);
            await prefs.setString(
              'login_time',
              DateTime.now().toIso8601String(),
            );

            // For backward compatibility, make sure explicitly_logged_out is false
            await prefs.setBool('explicitly_logged_out', false);

            // Set the token in memory
            _token = token;

            debugPrint(
              '✅ Login credentials successfully saved to SharedPreferences',
            );
            return data;
          } else {
            debugPrint('⚠️ WARNING: No token in login response!');
            return data;
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
    debugPrint('✅ Current user called');

    try {
      final prefs = await SharedPreferences.getInstance();

      // If we don't have a token in memory, try to load it from SharedPreferences
      if (_token == null || _token!.isEmpty) {
        _token = prefs.getString('auth_token');

        // If primary token is missing, try backup
        if (_token == null || _token!.isEmpty) {
          _token = prefs.getString('auth_token_backup');
        }

        // If no token found, return null immediately
        if (_token == null || _token!.isEmpty) {
          return null;
        }
      }

      // We have a token, try to validate it with the server
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final currentUserPath = _getApiEndpoint('/api/users/current');

      final response = await client.get(
        Uri.parse('$baseUrl$currentUserPath'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        // Token is valid, parse user data
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;

        // Update SharedPreferences with fresh data
        await prefs.setString(
          'user_id',
          responseBody['userId']?.toString() ?? "",
        );
        await prefs.setString('user_role', responseBody['role'] ?? 'USER');
        await prefs.setBool('is_logged_in', true);

        // Parse user ID from response
        int? userId;
        try {
          userId = (responseBody['userId'] as num).toInt();
        } catch (e) {
          userId = int.tryParse(responseBody['userId'].toString());
        }

        // Final check before returning
        if (userId == null) {
          debugPrint('⚠️ Could not get valid user ID from response');
          return null;
        }

        return {
          'userId': userId,
          'role': responseBody['role'] as String? ?? 'USER',
          // Include all other fields from the backend response
          ...responseBody,
        };
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _token = null;
        await prefs.remove('auth_token');
        await prefs.remove('auth_token_backup');
        throw AuthException('Session expired or unauthorized');
      } else {
        debugPrint('❌ Token validation failed (status ${response.statusCode})');
        _token = null;
        await prefs.remove('auth_token');
        await prefs.remove('auth_token_backup');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error getting current user: $e');
      return null;
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

  // Notification Preferences API methods
  Future<Map<String, dynamic>?> getNotificationPreferences(int userId) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await client.get(
        Uri.parse('$baseUrl/api/notification-preferences/$userId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint(
          'Error fetching notification preferences: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching notification preferences: $e');
      return null;
    }
  }

  Future<bool> updateDMNotificationPreferences(
    int userId, {
    required bool receiveDMNotifications,
    required bool emailDMNotifications,
    required bool pushDMNotifications,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await client.post(
        Uri.parse('$baseUrl/api/notification-preferences/$userId/dm'),
        headers: headers,
        body: jsonEncode({
          'receiveDMNotifications': receiveDMNotifications,
          'emailDMNotifications': emailDMNotifications,
          'pushDMNotifications': pushDMNotifications,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating DM notification preferences: $e');
      return false;
    }
  }

  Future<bool> updateGlobalNotificationPreferences(
    int userId, {
    required bool emailNotificationsEnabled,
    required bool pushNotificationsEnabled,
    required bool quietHoursEnabled,
    required String quietHoursStart,
    required String quietHoursEnd,
    required bool weekendNotifications,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await client.post(
        Uri.parse('$baseUrl/api/notification-preferences/$userId/global'),
        headers: headers,
        body: jsonEncode({
          'emailNotificationsEnabled': emailNotificationsEnabled,
          'pushNotificationsEnabled': pushNotificationsEnabled,
          'quietHoursEnabled': quietHoursEnabled,
          'quietHoursStart': quietHoursStart,
          'quietHoursEnd': quietHoursEnd,
          'weekendNotifications': weekendNotifications,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating global notification preferences: $e');
      return false;
    }
  }

  Future<bool> updateInvitationNotificationPreferences(
    int userId, {
    required bool receiveInvitationNotifications,
    required bool emailInvitationNotifications,
    required bool pushInvitationNotifications,
    required bool notifyOnInvitationAccepted,
    required bool notifyOnInvitationDeclined,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await client.post(
        Uri.parse('$baseUrl/api/notification-preferences/$userId/invitations'),
        headers: headers,
        body: jsonEncode({
          'receiveInvitationNotifications': receiveInvitationNotifications,
          'emailInvitationNotifications': emailInvitationNotifications,
          'pushInvitationNotifications': pushInvitationNotifications,
          'notifyOnInvitationAccepted': notifyOnInvitationAccepted,
          'notifyOnInvitationDeclined': notifyOnInvitationDeclined,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating invitation notification preferences: $e');
      return false;
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
  Future<Message> postMessage(
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

      // Only use familyId if explicitly provided - don't fetch from getUserById
      // This allows the backend to post to ALL families the user belongs to
      if (familyId == null) {
        debugPrint(
          'No explicit family ID provided - backend will post to all user families',
        );
      } else {
        debugPrint(
          'Explicit family ID provided: $familyId - posting to specific family only',
        );
      }

      // Use the new endpoint format
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

        // Only add familyId if explicitly provided
        if (familyId != null) {
          request.fields['familyId'] = familyId.toString();
          debugPrint('Adding explicit familyId field: $familyId');
        } else {
          debugPrint(
            'No familyId field added - backend will post to all families',
          );
        }
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
        final Map<String, dynamic> responseData = json.decode(responseString);
        return Message.fromJson(responseData);
      } else {
        debugPrint('❌ Failed to post message: $responseString');
        throw Exception('Failed to post message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception in postMessage: $e');
      rethrow; // or handle the error as needed
    }
  }

  // Post a message
  Future<Message> postComment(
    int userId,
    int parentMessageId,
    String content, {
    String? mediaPath,
    String? mediaType,
    int? familyId,
    String? videoUrl,
    String? thumbnailUrl,
  }) async {
    try {
      debugPrint('Starting postComment for parentMessageId: $parentMessageId');
      debugPrint('Content: "$content"');
      debugPrint('Media path: $mediaPath, media type: $mediaType');
      debugPrint('Video URL: $videoUrl, thumbnail URL: $thumbnailUrl');
      debugPrint('Explicit family ID provided: $familyId');

      // Only use familyId if explicitly provided - don't fetch from getUserById
      // This allows the backend to post to ALL families the user belongs to
      if (familyId == null) {
        debugPrint(
          'No explicit family ID provided - backend will post to all user families',
        );
      } else {
        debugPrint(
          'Explicit family ID provided: $familyId - posting to specific family only',
        );
      }

      // Use the new endpoint format
      final url = '$baseUrl/api/messages/$parentMessageId/comments';
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

        // Only add familyId if explicitly provided
        if (familyId != null) {
          request.fields['familyId'] = familyId.toString();
          debugPrint('Adding explicit familyId field: $familyId');
        } else {
          debugPrint(
            'No familyId field added - backend will post to all families',
          );
        }
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
        debugPrint('✅ Comment posted successfully');
        final Map<String, dynamic> responseData = json.decode(responseString);
        return Message.fromJson(responseData);
      } else {
        debugPrint('❌ Failed to post comment: $responseString');
        throw Exception('Failed to post comment: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception in postComment: $e');
      rethrow;
    }
  }

  // Post message with video processing
  Future<Message> postMessageWithVideoProcessing(
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
    Message newMessage = await postMessage(
      userId,
      content,
      mediaPath: effectiveMediaPath,
      mediaType: mediaType,
      familyId: familyId,
      // Pass the video data if available
      videoUrl: videoData?['videoUrl'],
      thumbnailUrl: videoData?['thumbnailUrl'],
    );

    return newMessage;
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

  // Get all family members across all families (for DM recipient selection)
  Future<List<Map<String, dynamic>>> getAllFamilyMembers() async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      debugPrint(
        '🔍 API DEBUG: Token available - ${_token!.substring(0, math.min(10, _token!.length))}...',
      );
    } else {
      debugPrint('🔍 API DEBUG: No token available!');
    }

    try {
      // Use the new endpoint for getting all family members
      final url = '$baseUrl/api/families/all-members';

      final response = await client.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final result =
            (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
        return result;
      } else if (response.statusCode == 400) {
        debugPrint(
          '🔍 API DEBUG: New endpoint returned 400 - returning empty list',
        );
        return [];
      } else {
        debugPrint(
          '🔍 API DEBUG: New endpoint failed with status ${response.statusCode}',
        );
        throw Exception('Failed to get all family members: ${response.body}');
      }
    } catch (e) {
      debugPrint('🔍 API DEBUG: Error fetching all family members: $e');
      return [];
    }
  }

  // Get family members (original method - for single family)
  Future<List<Map<String, dynamic>>> getFamilyMembers(int userId) async {
    debugPrint('🔍 API DEBUG: getFamilyMembers called for userId: $userId');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      debugPrint(
        '🔍 API DEBUG: Token available - ${_token!.substring(0, math.min(10, _token!.length))}...',
      );
    } else {
      debugPrint('🔍 API DEBUG: No token available!');
    }

    // First try to get the user's active family
    try {
      final userFamilies = await getJoinedFamilies(userId);

      if (userFamilies.isNotEmpty) {
        final familyId = userFamilies.first['familyId'];
        // Try the new family-based endpoint
        final url = '$baseUrl/api/families/$familyId/members';

        final response = await client.get(Uri.parse(url), headers: headers);

        if (response.statusCode == 200) {
          final result =
              (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
          return result;
        }
      } else {
        debugPrint('🔍 API DEBUG: No user families found');
      }
    } catch (e) {
      debugPrint(
        '🔍 API DEBUG: Family endpoint failed, falling back to old endpoint: $e',
      );
    }

    // Fallback to the old user-based endpoint
    final fallbackUrl = '$baseUrl/api/users/$userId/family-members';
    debugPrint('🔍 API DEBUG: Calling fallback endpoint: $fallbackUrl');

    final response = await client.get(Uri.parse(fallbackUrl), headers: headers);

    debugPrint(
      '🔍 API DEBUG: Fallback endpoint response status: ${response.statusCode}',
    );
    debugPrint(
      '🔍 API DEBUG: Fallback endpoint response body: ${response.body}',
    );

    if (response.statusCode == 200) {
      final result =
          (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      debugPrint(
        '🔍 API DEBUG: Fallback endpoint success - returning ${result.length} members',
      );
      return result;
    } else if (response.statusCode == 400) {
      debugPrint(
        '🔍 API DEBUG: Fallback endpoint returned 400 - returning empty list',
      );
      return [];
    } else {
      debugPrint(
        '🔍 API DEBUG: Fallback endpoint failed with status ${response.statusCode}',
      );
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

    debugPrint(
      '🔍 API: Responding to invitation $invitationId with accept=$accept',
    );
    debugPrint(
      '🔍 API: Using endpoint: $baseUrl/api/invitations/$invitationId/respond',
    );
    debugPrint('🔍 API: Request body: ${jsonEncode({'accept': accept})}');
    debugPrint('🔍 API: Headers: ${headers.toString()}');

    final response = await client.post(
      Uri.parse('$baseUrl/api/invitations/$invitationId/respond'),
      headers: headers,
      body: jsonEncode({'accept': accept}),
    );

    debugPrint('🔍 API: Response status: ${response.statusCode}');
    debugPrint('🔍 API: Response body: ${response.body}');

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

    debugPrint('🔍 API: Sending invitation to $email for family $familyId');

    // Using the InvitationController endpoint
    final response = await client.post(
      Uri.parse('$baseUrl/api/invitations/$familyId/invite'),
      headers: headers,
      body: jsonEncode({'email': email}),
    );

    debugPrint('🔍 API: Invitation response status: ${response.statusCode}');
    debugPrint('🔍 API: Invitation response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      // The enhanced response now includes:
      // - userExists: boolean
      // - suggestedEmails: List<String> (if userExists is false)
      // - message: enhanced message
      // - recipientName: String (if userExists is true)

      return responseData;
    } else {
      // Handle error response which may also include suggestions
      final errorData = jsonDecode(response.body) as Map<String, dynamic>;
      throw InvitationException(
        errorData['error'] ?? 'Failed to invite user',
        userExists: errorData['userExists'],
        suggestedEmails:
            (errorData['suggestedEmails'] as List<dynamic>?)?.cast<String>(),
      );
    }
  }

  // Invite a user to a specific family (takes family ID directly)
  Future<Map<String, dynamic>> inviteUserToFamily(
    int familyId,
    String email,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    debugPrint('🔍 API: Sending invitation to $email for family $familyId');

    // Using the InvitationController endpoint with the specified family ID
    final response = await client.post(
      Uri.parse('$baseUrl/api/invitations/$familyId/invite'),
      headers: headers,
      body: jsonEncode({'email': email}),
    );

    debugPrint('🔍 API: Invitation response status: ${response.statusCode}');
    debugPrint('🔍 API: Invitation response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return responseData;
    } else if (response.statusCode == 403) {
      // Token might be expired, try to get a fresh one
      debugPrint('🔑 Token expired, trying to get fresh test token');
      final freshToken = await getTestToken();
      if (freshToken != null) {
        // Retry the invitation with the fresh token
        debugPrint('🔍 Retrying invitation with fresh token');
        final retryResponse = await client.post(
          Uri.parse('$baseUrl/api/invitations/$familyId/invite'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          body: jsonEncode({'email': email}),
        );

        debugPrint(
          '🔍 API: Retry invitation response status: ${retryResponse.statusCode}',
        );
        debugPrint(
          '🔍 API: Retry invitation response body: ${retryResponse.body}',
        );

        if (retryResponse.statusCode == 200 ||
            retryResponse.statusCode == 201) {
          final responseData =
              jsonDecode(retryResponse.body) as Map<String, dynamic>;
          return responseData;
        } else {
          // Handle error response from retry
          final errorData =
              jsonDecode(retryResponse.body) as Map<String, dynamic>;
          throw InvitationException(
            errorData['error'] ?? 'Failed to invite user after token refresh',
            userExists: errorData['userExists'],
            suggestedEmails:
                (errorData['suggestedEmails'] as List<dynamic>?)
                    ?.cast<String>(),
          );
        }
      }
      // If token refresh failed, throw the original error
      throw InvitationException(
        'Authentication failed - please try logging out and back in',
        userExists: false,
        suggestedEmails: null,
      );
    } else {
      // Handle error response which may also include suggestions
      final errorData = jsonDecode(response.body) as Map<String, dynamic>;
      throw InvitationException(
        errorData['error'] ?? 'Failed to invite user',
        userExists: errorData['userExists'],
        suggestedEmails:
            (errorData['suggestedEmails'] as List<dynamic>?)?.cast<String>(),
      );
    }
  }

  // Get family owned by a user
  Future<Map<String, dynamic>?> getOwnedFamily(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    try {
      // Use the new dedicated endpoint for checking owned family
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/owned'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null; // User doesn't own a family
      }
    } catch (e) {
      debugPrint('Error checking owned family: $e');
    }

    return null; // User doesn't own a family
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
      Uri.parse('$baseUrl/api/users/$userId/profile'),
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
        Uri.parse('$baseUrl/api/invitations'),
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

  // Get sent invitations by the current user
  Future<Map<String, dynamic>> getSentInvitations() async {
    debugPrint('Getting sent invitations from backend endpoint');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting sent invitations');
      return {'success': false, 'invitations': []};
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/invitations/sent'),
        headers: headers,
      );

      debugPrint('Sent invitations response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        debugPrint(
          'Sent invitations endpoint not found (404): ${response.body}',
        );
        return {'success': false, 'invitations': []};
      } else {
        debugPrint('Failed to get sent invitations: ${response.body}');
        return {'success': false, 'invitations': []};
      }
    } catch (e) {
      debugPrint('Error fetching sent invitations: $e');
      return {'success': false, 'invitations': []};
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
      body: jsonEncode({'name': familyName}),
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

    // First get the user's active family to determine which family to leave
    try {
      final userFamilies = await getJoinedFamilies(userId);
      if (userFamilies.isNotEmpty) {
        final familyId = userFamilies.first['familyId'];

        // Try the new family-based endpoint
        final response = await client.post(
          Uri.parse('$baseUrl/api/families/$familyId/leave'),
          headers: headers,
        );

        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint(
        'New family leave endpoint failed, falling back to old endpoint: $e',
      );
    }

    // Fallback to the old user-based endpoint
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

  // Join a family
  Future<void> joinFamily(int userId, int familyId) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    // Try the new family-based endpoint first
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/families/$familyId/join'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return; // Success
      }
    } catch (e) {
      debugPrint(
        'New family join endpoint failed, falling back to old endpoint: $e',
      );
    }

    // Fallback to the old user-based endpoint
    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/join-family/$familyId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to join family: ${response.body}');
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
        final memberFamilyId = member['familyId'];

        // Only include members of this family - handle type conversion
        final memberFamilyIdInt =
            memberFamilyId is int
                ? memberFamilyId
                : int.tryParse(memberFamilyId.toString()) ?? -1;

        debugPrint(
          'ApiService: Comparing familyId $familyId with memberFamilyId $memberFamilyIdInt (original: $memberFamilyId, type: ${memberFamilyId.runtimeType})',
        );

        if (memberFamilyIdInt == familyId) {
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
                member['role'] == 'ADMIN' ||
                member['role'] == 'FAMILY_ADMIN' ||
                member['isOwner'] == true,
            'memberOfFamilyName':
                member['familyName'] ??
                familyDetails?['name'] ??
                'Unknown Family',
            'userId': userId,
            'joinedAt':
                DateTime.now(), // TODO: Get actual join date from backend
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

      final response = await client.get(url, headers: headers);
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

  // Message-related methods
  Future<List<Message>> getUserMessages(String userId) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/users/$userId/messages'),
        headers: {
          'Accept': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final messages =
            jsonList.map((json) {
              return Message.fromJson(json);
            }).toList();

        return messages;

        //       return jsonList.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting user messages: $e');
      rethrow;
    }
  }

  // Get comments for a message
  Future<List<Message>> getComments(String messageId) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/messages/$messageId/comments'),
        headers: {
          'Accept': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting user messages: $e');
      rethrow;
    }
  }

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

      final response = await client.post(url, headers: headers);
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

      final response = await client.delete(url, headers: headers);
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

      final response = await client.post(url, headers: headers, body: body);
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

  Future<List<Message>> getMessageReplies(String messageId) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/comments/$messageId/comments'),
        headers: {
          'Accept': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load replies: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting message replies: $e');
      rethrow;
    }
  }

  Future<Message> createMessage(
    String userId,
    String text, {
    String? mediaUrl,
  }) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/messages'),
        headers: {
          'Content-Type': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'text': text,
          if (mediaUrl != null) 'mediaUrl': mediaUrl,
        }),
      );

      if (response.statusCode == 201) {
        return Message.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating message: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> toggleMessageLike(
    String messageId,
    bool isLiked,
  ) async {
    debugPrint('Toggling like for message $messageId: isLiked=$isLiked');
    final response = await client.post(
      Uri.parse('$baseUrl/api/messages/$messageId/message_like'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'liked': isLiked}),
    );

    debugPrint(
      'Toggle like response: status=${response.statusCode}, body=${response.body}',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle like: ${response.body}');
    }

    // Parse and return the response body
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> toggleMessageLove(
    String messageId,
    bool isLoved,
  ) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/messages/$messageId/message_love'),
        headers: {
          'Accept': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'loved': isLoved,
        }), // Changed from isLoved to loved to match backend
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error toggling message love: $e');
      return null;
    }
  }

  Future<void> toggleCommentLike(String messageId, bool isLiked) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/messages/$messageId/comment_like'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'liked': isLiked}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle like: ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> toggleCommentLove(
    String messageId,
    bool isLoved,
  ) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/messages/$messageId/comment_love'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'loved': isLoved}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle love: ${response.body}');
    }

    return json.decode(response.body);
  }

  // ===== DIRECT MESSAGE (DM) METHODS =====

  /// Get or create a conversation with another user
  /// Returns conversation details including the other user info
  Future<DMConversation?> getOrCreateConversation(int otherUserId) async {
    try {
      debugPrint('Getting/creating conversation with user: $otherUserId');

      final url = Uri.parse('$baseUrl/api/dm/conversations/$otherUserId');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.post(url, headers: headers);
      debugPrint(
        'Get/create conversation response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Extract conversation ID and other user details
        final conversationId = data['conversation_id'] as int?;
        final otherUser = data['other_user'] as Map<String, dynamic>?;

        if (conversationId == null || otherUser == null) return null;

        // Get current user ID
        final currentUser = await getCurrentUser();
        final currentUserId = currentUser?['userId'] as int?;
        if (currentUserId == null) return null;

        // Get other user ID from the otherUser map
        final otherUserId = otherUser['id'] as int;

        // Determine user1Id and user2Id (lower ID is always user1)
        final user1Id =
            currentUserId < otherUserId ? currentUserId : otherUserId;
        final user2Id =
            currentUserId < otherUserId ? otherUserId : currentUserId;

        // Create DMConversation object using fromJson
        return DMConversation.fromJson({
          'id': conversationId,
          'user1_id': user1Id,
          'user2_id': user2Id,
          'created_at': data['created_at'],
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'other_user_name': otherUser['username'],
          'other_user_first_name': otherUser['first_name'],
          'other_user_last_name': otherUser['last_name'],
        });
      } else {
        debugPrint('Failed to get/create conversation: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting/creating conversation: $e');
      return null;
    }
  }

  /// Get all conversations for the current user
  /// Returns list of conversations with other user details and last message info
  Future<List<DMConversation>> getDMConversations() async {
    try {
      debugPrint('🚀 Getting DM conversations');

      final url = Uri.parse('$baseUrl/api/dm/conversations');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.get(url, headers: headers);
      debugPrint(
        '📥 Get conversations response: status=${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final conversations = data['conversations'] as List<dynamic>;

        debugPrint('📊 Raw conversations data: $conversations');

        // Get current user ID from provider
        final currentUser = await getCurrentUser();
        final currentUserId = currentUser?['userId'] as int?;

        if (currentUserId == null) {
          debugPrint('❌ No current user ID available from provider');
          return [];
        }

        debugPrint('👤 Current user ID from provider: $currentUserId');

        final result =
            conversations
                .map((conv) {
                  try {
                    debugPrint('🔄 Processing conversation: $conv');

                    // Use the new flat format from backend
                    final conversationData = Map<String, dynamic>.from(conv);

                    // Create DMConversation object using fromJson with the backend format
                    final dmConversation = DMConversation.fromJson(
                      conversationData,
                    );

                    debugPrint(
                      '✅ Created DMConversation: ${dmConversation.otherUserName} - "${dmConversation.lastMessageContent}" - Group: ${dmConversation.isGroup}',
                    );
                    return dmConversation;
                  } catch (e) {
                    debugPrint('❌ Error parsing conversation: $e');
                    return null;
                  }
                })
                .whereType<DMConversation>()
                .toList();

        debugPrint('🎉 Returning ${result.length} DM conversations');
        return result;
      } else {
        debugPrint('❌ Failed to get conversations: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('💥 Error getting conversations: $e');
      return [];
    }
  }

  /// Search DM conversations and messages
  /// Returns list of conversations matching the search query
  Future<List<DMConversation>> searchDMConversations(String query) async {
    debugPrint('🔍 DM SEARCH: Starting DM conversation search for "$query"');

    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final url = '$baseUrl/api/dm/search?q=${Uri.encodeComponent(query)}';
    debugPrint('🔍 DM SEARCH: Calling URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    debugPrint('🔍 DM SEARCH: Response status: ${response.statusCode}');
    debugPrint('🔍 DM SEARCH: Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final conversations = data['conversations'] as List<dynamic>;

      debugPrint('🔍 DM SEARCH: Found ${conversations.length} conversations');

      // Log each conversation for debugging
      for (int i = 0; i < conversations.length; i++) {
        final conv = conversations[i];
        debugPrint('🔍 DM SEARCH: Conversation $i: $conv');

        // Check if it's a group chat
        if (conv['is_group'] == true) {
          debugPrint('🔍 DM SEARCH: Group chat detected: ${conv['name']}');
        } else {
          debugPrint('🔍 DM SEARCH: 1:1 chat detected');
        }
      }

      try {
        final dmConversations =
            conversations
                .map((json) {
                  try {
                    final dmConv = DMConversation.fromJson(json);
                    debugPrint(
                      '🔍 DM SEARCH: Successfully parsed: ${dmConv.isGroup ? "Group '${dmConv.name}'" : "1:1 chat"}',
                    );
                    return dmConv;
                  } catch (e) {
                    debugPrint('❌ DM SEARCH: Failed to parse conversation: $e');
                    debugPrint('❌ DM SEARCH: Failed JSON: $json');
                    return null;
                  }
                })
                .where((conv) => conv != null)
                .cast<DMConversation>()
                .toList();

        debugPrint(
          '🔍 DM SEARCH: Final result count: ${dmConversations.length}',
        );
        return dmConversations;
      } catch (e) {
        debugPrint('❌ DM SEARCH: Error mapping conversations: $e');
        return [];
      }
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to search conversations');
    }
  }

  /// Send a DM message (text or media) using the new postMessage endpoint
  /// Returns the sent message details
  Future<Map<String, dynamic>?> sendDMMessage({
    required int conversationId,
    String? content,
    String? mediaPath,
    String? mediaType,
    String? videoUrl,
  }) async {
    try {
      debugPrint(
        '🚀 sendDMMessage called with: conversationId=$conversationId, content="$content", mediaPath="$mediaPath", mediaType="$mediaType", videoUrl="$videoUrl"',
      );

      // Use the userId from current auth
      final currentUser = await getCurrentUser();
      if (currentUser == null || currentUser['userId'] == null) {
        debugPrint('❌ No current user ID available');
        return null;
      }
      final userId = currentUser['userId'] as int;

      final url = Uri.parse('$baseUrl/api/dm/$userId/message');
      debugPrint('🌐 Making request to: $url');

      var request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer $_token';

      // Add required fields
      request.fields['content'] = content ?? '';
      request.fields['conversationId'] = conversationId.toString();
      debugPrint('📝 Request fields: ${request.fields}');

      // Add media file if provided
      if (mediaPath != null && mediaPath.isNotEmpty) {
        final file = File(mediaPath);
        if (await file.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath('media', mediaPath),
          );
          if (mediaType != null) {
            request.fields['mediaType'] = mediaType;
          }
          debugPrint('📎 Added media file: $mediaPath (type: $mediaType)');
        } else {
          debugPrint('❌ Media file does not exist: $mediaPath');
        }
      }

      // Add video URL if provided (for external videos)
      if (videoUrl != null && videoUrl.isNotEmpty) {
        request.fields['videoUrl'] = videoUrl;
        debugPrint('🎥 Added video URL: $videoUrl');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint(
        '📥 Send DM message response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('❌ Failed to send DM message: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('💥 Error sending DM message: $e');
      return null;
    }
  }

  /// Get messages for a conversation with pagination
  /// Returns messages and pagination info
  Future<Map<String, dynamic>?> getDMMessages({
    required int conversationId,
    int page = 0,
    int size = 50,
  }) async {
    try {
      debugPrint(
        'Getting DM messages for conversation: $conversationId (page: $page, size: $size)',
      );

      final url = Uri.parse(
        '$baseUrl/api/dm/conversations/$conversationId/messages?page=$page&size=$size',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        debugPrint('Failed to get DM messages: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting DM messages: $e');
      return null;
    }
  }

  /// Mark all messages in a conversation as read
  /// Returns the number of messages marked as read
  Future<int> markDMConversationAsRead(int conversationId) async {
    try {
      debugPrint('Marking DM conversation as read: $conversationId');

      final url = Uri.parse(
        '$baseUrl/api/dm/conversations/$conversationId/read',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.put(url, headers: headers);
      debugPrint(
        'Mark DM conversation as read response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['markedAsRead'] as int? ?? 0;
      } else {
        debugPrint('Failed to mark DM conversation as read: ${response.body}');
        return 0;
      }
    } catch (e) {
      debugPrint('Error marking DM conversation as read: $e');
      return 0;
    }
  }

  // ===== NOTIFICATION METHODS =====

  /// Register FCM token for push notifications
  Future<bool> registerFcmToken(String userId, String fcmToken) async {
    try {
      debugPrint('📤 Registering FCM token for user: $userId');

      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/fcm-token'),
        headers: headers,
        body: json.encode({'fcmToken': fcmToken}),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM token registered successfully');
        return true;
      } else {
        debugPrint(
          '⚠️ Failed to register FCM token: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error registering FCM token: $e');
      return false;
    }
  }

  // ===== SEARCH METHODS =====

  /// Get a fresh test token (for development/testing)
  Future<Map<String, dynamic>?> getTestToken() async {
    try {
      debugPrint('🔑 Getting fresh test token');

      final response = await client.get(
        Uri.parse('$baseUrl/api/users/test-token'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Got fresh test token for user: ${data['username']}');

        // Save the new token
        if (data['token'] != null) {
          await _saveToken(data['token']);
        }

        return data;
      } else {
        debugPrint('❌ Failed to get test token: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('💥 Error getting test token: $e');
      return null;
    }
  }

  /// Search messages within user's families
  /// Returns list of messages matching the search query
  Future<List<Map<String, dynamic>>> searchMessages({
    required String query,
    int? familyId,
    int page = 0,
    int size = 20,
  }) async {
    try {
      debugPrint(
        '🔍 Searching messages: "$query", familyId: $familyId, page: $page',
      );

      final queryParams = <String, String>{
        'q': query,
        'page': page.toString(),
        'size': size.toString(),
      };

      if (familyId != null) {
        queryParams['familyId'] = familyId.toString();
      }

      final uri = Uri.parse(
        '$baseUrl/api/search/messages',
      ).replace(queryParameters: queryParams);
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.get(uri, headers: headers);
      debugPrint('🔍 Search response: status=${response.statusCode}');

      if (response.statusCode == 200) {
        final results =
            (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
        debugPrint('🔍 Found ${results.length} search results');
        return results;
      } else if (response.statusCode == 403) {
        // Token might be expired, try to get a fresh one
        debugPrint('🔑 Token expired, trying to get fresh test token');
        final freshToken = await getTestToken();
        if (freshToken != null) {
          // Retry the search with the fresh token
          debugPrint('🔍 Retrying search with fresh token');
          final retryResponse = await client.get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
          );

          if (retryResponse.statusCode == 200) {
            final results =
                (jsonDecode(retryResponse.body) as List)
                    .cast<Map<String, dynamic>>();
            debugPrint(
              '🔍 Found ${results.length} search results after token refresh',
            );
            return results;
          }
        }
        debugPrint(
          '❌ Search failed even after token refresh: ${response.body}',
        );
        return [];
      } else {
        debugPrint('❌ Search failed: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('💥 Error searching messages: $e');
      return [];
    }
  }

  /// Get user's families for search filter
  Future<List<Map<String, dynamic>>> getSearchFamilies() async {
    try {
      debugPrint('🔍 Getting user families for search filter');

      final url = Uri.parse('$baseUrl/api/search/families');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.get(url, headers: headers);
      debugPrint('🔍 Get families response: status=${response.statusCode}');

      if (response.statusCode == 200) {
        final families =
            (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
        debugPrint('🔍 Found ${families.length} families for search');
        return families;
      } else if (response.statusCode == 403) {
        // Token might be expired, try to get a fresh one
        debugPrint('🔑 Token expired, trying to get fresh test token');
        final freshToken = await getTestToken();
        if (freshToken != null) {
          // Retry the request with the fresh token
          debugPrint('🔍 Retrying get families with fresh token');
          final retryResponse = await client.get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
          );

          if (retryResponse.statusCode == 200) {
            final families =
                (jsonDecode(retryResponse.body) as List)
                    .cast<Map<String, dynamic>>();
            debugPrint(
              '🔍 Found ${families.length} families after token refresh',
            );
            return families;
          }
        }
        debugPrint(
          '❌ Failed to get search families even after token refresh: ${response.body}',
        );
        return [];
      } else {
        debugPrint('❌ Failed to get search families: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('💥 Error getting search families: $e');
      return [];
    }
  }

  /// Test the search controller endpoint
  Future<Map<String, dynamic>?> testSearchController() async {
    try {
      debugPrint('🔍 Testing search controller endpoint');

      final response = await client.get(
        Uri.parse('$baseUrl/api/search/test'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        '🔍 Search test response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Search controller test successful: ${data['message']}');
        return data;
      } else {
        debugPrint('❌ Search controller test failed: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('💥 Error testing search controller: $e');
      return null;
    }
  }

  // Get complete family data in one call - families, members, and preferences
  Future<Map<String, dynamic>> getCompleteFamilyData() async {
    debugPrint('🔍 API: Getting complete family data');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      throw Exception('No authentication token available');
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/complete-data'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint(
          '🔍 API: Retrieved complete family data - ${result['families']?.length ?? 0} families, ${result['members']?.length ?? 0} members',
        );
        return result;
      } else {
        throw Exception('Failed to get complete family data: ${response.body}');
      }
    } catch (e) {
      debugPrint('🔍 API: Error getting complete family data: $e');
      rethrow;
    }
  }

  // Get upcoming birthdays for a family (next 7 days)
  Future<List<Map<String, dynamic>>> getUpcomingBirthdays(int familyId) async {
    debugPrint('Getting upcoming birthdays for family $familyId');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting birthdays');
      return [];
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/$familyId/birthdays'),
        headers: headers,
      );

      debugPrint('Birthdays response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> birthdays =
            jsonDecode(response.body) as List<dynamic>;
        return birthdays.cast<Map<String, dynamic>>();
      } else if (response.statusCode == 404) {
        debugPrint('Birthdays endpoint not found (404): ${response.body}');
        return [];
      } else {
        debugPrint('Failed to get birthdays: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching birthdays: $e');
      return [];
    }
  }

  // Get weekly activity data for a family (past 7 days)
  Future<Map<String, dynamic>?> getWeeklyActivity(int familyId) async {
    debugPrint('Getting weekly activity for family $familyId');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting weekly activity');
      return null;
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/$familyId/weekly-activity'),
        headers: headers,
      );

      debugPrint('Weekly activity response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> activity =
            jsonDecode(response.body) as Map<String, dynamic>;
        return activity;
      } else if (response.statusCode == 404) {
        debugPrint(
          'Weekly activity endpoint not found (404): ${response.body}',
        );
        return null;
      } else {
        debugPrint('Failed to get weekly activity: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching weekly activity: $e');
      return null;
    }
  }

  // Get monthly activity data for a family (past 30 days)
  Future<Map<String, dynamic>?> getMonthlyActivity(int familyId) async {
    debugPrint('Getting monthly activity for family $familyId');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting monthly activity');
      return null;
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/$familyId/monthly-activity'),
        headers: headers,
      );

      debugPrint('Monthly activity response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> activity =
            jsonDecode(response.body) as Map<String, dynamic>;
        return activity;
      } else if (response.statusCode == 404) {
        debugPrint(
          'Monthly activity endpoint not found (404): ${response.body}',
        );
        return null;
      } else {
        debugPrint('Failed to get monthly activity: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching monthly activity: $e');
      return null;
    }
  }

  // Get yearly activity data for a family (past 12 months)
  Future<Map<String, dynamic>?> getYearlyActivity(int familyId) async {
    debugPrint('Getting yearly activity for family $familyId');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting yearly activity');
      return null;
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/$familyId/yearly-activity'),
        headers: headers,
      );

      debugPrint('Yearly activity response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> activity =
            jsonDecode(response.body) as Map<String, dynamic>;
        return activity;
      } else if (response.statusCode == 404) {
        debugPrint(
          'Yearly activity endpoint not found (404): ${response.body}',
        );
        return null;
      } else {
        debugPrint('Failed to get yearly activity: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching yearly activity: $e');
      return null;
    }
  }

  // Get multi-year activity data for a family (past 5 years)
  Future<Map<String, dynamic>?> getMultiYearActivity(int familyId) async {
    debugPrint('Getting multi-year activity for family $familyId');

    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    } else {
      debugPrint('No token available for getting multi-year activity');
      return null;
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/families/$familyId/multi-year-activity'),
        headers: headers,
      );

      debugPrint('Multi-year activity response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> activity =
            jsonDecode(response.body) as Map<String, dynamic>;
        return activity;
      } else if (response.statusCode == 404) {
        debugPrint(
          'Multi-year activity endpoint not found (404): ${response.body}',
        );
        return null;
      } else {
        debugPrint('Failed to get multi-year activity: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching multi-year activity: $e');
      return null;
    }
  }

  // Enable all notification preferences for onboarding
  Future<bool> enableAllNotificationPreferences(int userId) async {
    try {
      debugPrint(
        '🔔 API_SERVICE: Starting enableAllNotificationPreferences for user $userId',
      );

      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
        debugPrint(
          '🔔 API_SERVICE: Using auth token: ${_token?.substring(0, 20)}...',
        );
      } else {
        debugPrint('❌ API_SERVICE: No auth token available!');
      }

      final url = '$baseUrl/api/notification-preferences/$userId/enable-all';
      debugPrint('🔔 API_SERVICE: Making POST request to: $url');

      final response = await client.post(Uri.parse(url), headers: headers);

      debugPrint('🔔 API_SERVICE: Response status: ${response.statusCode}');
      debugPrint('🔔 API_SERVICE: Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ All notification preferences enabled for user $userId');
        return true;
      } else {
        debugPrint(
          '❌ Failed to enable notification preferences: ${response.statusCode}',
        );
        debugPrint('Response body: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error enabling all notification preferences: $e');
      return false;
    }
  }

  // Simplified notification preferences update method
  Future<bool> updateNotificationPreferences(
    int userId,
    Map<String, bool> preferences,
  ) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await client.post(
        Uri.parse('$baseUrl/api/notification-preferences/$userId'),
        headers: headers,
        body: jsonEncode(preferences),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating notification preferences: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error in forgotPassword: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> forgotUsername(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/forgot-username'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error in forgotUsername: $e');
      return null;
    }
  }

  /// Change user password
  Future<Map<String, dynamic>?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      debugPrint('Attempting to change password');

      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/users/change-password'),
        headers: headers,
        body: json.encode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );

      debugPrint('Change password response status: ${response.statusCode}');
      debugPrint('Change password response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 400) {
        // Return the error message from the backend
        final errorData = jsonDecode(response.body);
        return {'error': errorData['error']};
      } else {
        return {'error': 'Failed to change password. Please try again.'};
      }
    } catch (e) {
      debugPrint('Error in changePassword: $e');
      return {'error': 'An error occurred while changing password.'};
    }
  }

  /// Force clear ALL authentication data (for debugging corrupted state)
  Future<void> forceClearAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      debugPrint('🧹 FORCE CLEARING: Starting complete auth data wipe...');

      // Clear all auth-related keys
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');
      await prefs.remove('user_id');
      await prefs.remove('user_role');
      await prefs.remove('is_logged_in');
      await prefs.remove('login_time');
      await prefs.remove('last_token_validation');
      await prefs.setBool('explicitly_logged_out', true);

      // Clear token from memory
      _token = null;

      debugPrint('🧹 FORCE CLEARING: All auth data cleared');

      // Verify clearing worked
      final remainingKeys = prefs.getKeys();
      final authKeys =
          remainingKeys
              .where(
                (key) =>
                    key.contains('auth_token') ||
                    key.contains('user_id') ||
                    key.contains('user_role') ||
                    key.contains('is_logged_in'),
              )
              .toList();

      if (authKeys.isEmpty) {
        debugPrint(
          '✅ FORCE CLEARING: Verification successful - no auth keys remain',
        );
      } else {
        debugPrint(
          '❌ FORCE CLEARING: Warning - some auth keys still exist: $authKeys',
        );
      }
    } catch (e) {
      debugPrint('❌ FORCE CLEARING: Error: $e');
    }
  }

  /// Get just the current user ID (for notification filtering)
  Future<String?> getCurrentUserId() async {
    try {
      final userData = await getCurrentUser();
      if (userData != null && userData['userId'] != null) {
        return userData['userId'].toString();
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting current user ID: $e');
      return null;
    }
  }

  /// Debug FCM token (just logs, no database changes)
  Future<bool> debugFcmToken(String userId, String fcmToken) async {
    try {
      debugPrint('🔍 API_DEBUG: Calling FCM debug endpoint for user: $userId');
      debugPrint('🔍 API_DEBUG: Token length: ${fcmToken.length}');
      debugPrint('🔍 API_DEBUG: Full FCM token being sent: $fcmToken');

      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final requestBody = json.encode({'fcmToken': fcmToken});
      debugPrint('🔍 API_DEBUG: Request body: $requestBody');
      debugPrint(
        '🔍 API_DEBUG: Sending to URL: $baseUrl/api/users/$userId/fcm-token-debug',
      );

      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/fcm-token-debug'),
        headers: headers,
        body: requestBody,
      );

      debugPrint('🔍 API_DEBUG: Response status: ${response.statusCode}');
      debugPrint('🔍 API_DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ API_DEBUG: Debug endpoint call successful');
        return true;
      } else {
        debugPrint(
          '⚠️ API_DEBUG: Debug endpoint failed: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ API_DEBUG: Error calling debug endpoint: $e');
      return false;
    }
  }

  /// Simple debug print to backend logs
  Future<bool> printToBackend(String message) async {
    try {
      final headers = {'Content-Type': 'application/json'};

      final response = await client.post(
        Uri.parse('$baseUrl/api/users/test/print'),
        headers: headers,
        body: json.encode({'message': message}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error sending debug message to backend: $e');
      return false;
    }
  }

  /// Simple function to print a string to backend logs
  Future<void> backendDebugPrint(String message) async {
    try {
      final headers = {'Content-Type': 'application/json'};

      await client.post(
        Uri.parse('$baseUrl/public/print'),
        headers: headers,
        body: json.encode({'message': message}),
      );
    } catch (e) {
      debugPrint('❌ backendDebugPrint error: $e');
    }
  }

  // Mark multiple messages as viewed in a single API call (batch operation)
  Future<Map<String, dynamic>> markMultipleMessagesAsViewed(
    List<int> messageIds,
  ) async {
    if (messageIds.isEmpty) {
      debugPrint(
        'Error: Cannot mark messages as viewed - Message IDs list is empty',
      );
      return {'error': 'Message IDs list is empty'};
    }

    if (messageIds.length > 50) {
      debugPrint('Error: Cannot mark more than 50 messages at once');
      return {'error': 'Too many message IDs'};
    }

    debugPrint(
      'Batch marking ${messageIds.length} messages as viewed: $messageIds',
    );

    try {
      final url = Uri.parse('$baseUrl/api/messages/batch-views');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final requestBody = {'messageIds': messageIds};

      final response = await client.post(
        url,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      debugPrint(
        'Batch mark messages as viewed response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to batch mark messages as viewed: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error batch marking messages as viewed: $e');
      return {'error': e.toString()};
    }
  }

  // Get unread message count for user (optionally for specific family)
  Future<Map<String, dynamic>> getUnreadMessageCount({int? familyId}) async {
    debugPrint(
      'Getting unread message count${familyId != null ? ' for family $familyId' : ''}',
    );

    try {
      String url = '$baseUrl/api/messages/unread-count';
      if (familyId != null) {
        url += '?familyId=$familyId';
      }

      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        'Unread count response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get unread count: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return {'error': e.toString()};
    }
  }

  // Get unread message count breakdown by family
  Future<Map<String, dynamic>> getUnreadMessageCountByFamily() async {
    debugPrint('Getting unread message count by family');

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/messages/unread-by-family'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        'Unread by family response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to get unread count by family: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error getting unread count by family: $e');
      return {'error': e.toString()};
    }
  }

  // =================================
  // DM Message View Tracking Methods
  // =================================

  // Mark multiple DM messages as viewed in a single API call (batch operation)
  Future<Map<String, dynamic>> markMultipleDMMessagesAsViewed(
    List<int> dmMessageIds,
  ) async {
    if (dmMessageIds.isEmpty) {
      debugPrint(
        'Error: Cannot mark DM messages as viewed - Message IDs list is empty',
      );
      return {'error': 'DM Message IDs list is empty'};
    }

    if (dmMessageIds.length > 50) {
      debugPrint('Error: Cannot mark more than 50 DM messages at once');
      return {'error': 'Too many DM message IDs'};
    }

    debugPrint(
      'Batch marking ${dmMessageIds.length} DM messages as viewed: $dmMessageIds',
    );

    try {
      final url = Uri.parse('$baseUrl/api/messages/dm/batch-views');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final requestBody = {'dmMessageIds': dmMessageIds};

      final response = await client.post(
        url,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      debugPrint(
        'Batch mark DM messages as viewed response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to batch mark DM messages as viewed: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error batch marking DM messages as viewed: $e');
      return {'error': e.toString()};
    }
  }

  // Mark single DM message as viewed
  Future<Map<String, dynamic>> markDMMessageAsViewed(int dmMessageId) async {
    debugPrint('Marking DM message $dmMessageId as viewed');

    try {
      final url = Uri.parse('$baseUrl/api/messages/dm/$dmMessageId/views');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final response = await client.post(url, headers: headers);

      debugPrint(
        'Mark DM message as viewed response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to mark DM message as viewed: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error marking DM message as viewed: $e');
      return {'error': e.toString()};
    }
  }

  // Get unread DM message count for user
  Future<Map<String, dynamic>> getUnreadDMMessageCount() async {
    debugPrint('Getting unread DM message count');

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/messages/dm/unread-count'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint(
        'Unread DM count response: status=${response.statusCode}, body=${response.body}',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get unread DM count: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting unread DM count: $e');
      return {'error': e.toString()};
    }
  }

  // Create group chat
  Future<Map<String, dynamic>?> createGroupChat({
    required String? groupName,
    required List<int> participantIds,
  }) async {
    try {
      if (_token == null || _token!.isEmpty) {
        debugPrint('❌ API: No auth token available for group chat creation');
        return null;
      }

      final url = Uri.parse('$baseUrl/api/dm/groups');

      final body = {'name': groupName, 'participantIds': participantIds};

      debugPrint(
        '🔄 API: Creating group chat with ${participantIds.length} participants',
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode(body),
      );

      debugPrint(
        '📡 API: Group chat creation response status: ${response.statusCode}',
      );

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint(
          '✅ API: Group chat created successfully - ID: ${responseData['id']}',
        );
        return responseData;
      } else {
        debugPrint(
          '❌ API: Failed to create group chat: ${response.statusCode}',
        );
        debugPrint('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ API: Exception creating group chat: $e');
      return null;
    }
  }

  // Add participants to a group chat
  Future<Map<String, dynamic>> addGroupParticipants(
    int conversationId,
    List<int> participantIds,
  ) async {
    final url = '$baseUrl/api/dm/groups/$conversationId/participants';
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'participantIds': participantIds}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to add participants');
    }
  }

  // Remove a participant from a group chat
  Future<Map<String, dynamic>> removeGroupParticipant(
    int conversationId,
    int participantId,
  ) async {
    final url =
        '$baseUrl/api/dm/groups/$conversationId/participants/$participantId';
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.delete(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to remove participant');
    }
  }

  // Get group chat configuration
  Future<Map<String, dynamic>> getGroupChatConfig() async {
    final url = '$baseUrl/api/dm/config';

    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to get group chat config');
    }
  }
}
