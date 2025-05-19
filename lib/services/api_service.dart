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
    debugPrint("✅✅✅ USING API BASE URL: $url");
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
   - Android Emulator: 10.0.2.2:8080
   - iOS Simulator: localhost:8080
   - Physical Device: Your computer's IP address (e.g., 10.0.0.10)
3. Go to Profile -> Server Configuration to set the correct server URL.
4. Is your device/emulator connected to the same WiFi network?
5. Are there any firewall settings blocking the connection?
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
      // Clear token from memory
      _token = null;

      // Clear all auth-related data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Remove all authentication data
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');
      await prefs.remove('user_id');
      await prefs.remove('user_role');
      await prefs.remove('is_logged_in');
      await prefs.remove('login_time');

      // For backward compatibility, still set this flag
      await prefs.setBool('explicitly_logged_out', true);

      debugPrint('✅ User successfully logged out - all auth data cleared');
    } catch (e) {
      debugPrint('❌ Error during logout: $e');
      // Simple fallback in case of error
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        _token = null;
        debugPrint('✅ User logged out through fallback method');
      } catch (secondError) {
        debugPrint('❌ Fatal error during logout: $secondError');
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

      // Get SharedPreferences instance
      final prefs = await SharedPreferences.getInstance();

      // Clear any existing auth data to start fresh
      await prefs.remove('auth_token');
      await prefs.remove('auth_token_backup');

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
    debugPrint('Checking for current user');

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
          debugPrint('No valid token found in SharedPreferences');
          return null;
        }

        debugPrint('Loaded token from SharedPreferences');
      }

      // We have a token, try to validate it with the server
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

      final currentUserPath = _getApiEndpoint('/api/users/current');
      debugPrint('Validating token with server: $baseUrl$currentUserPath');

      final response = await client.get(
        Uri.parse('$baseUrl$currentUserPath'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        // Token is valid, parse user data
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Current user validated successfully');

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
        };
      } else {
        // Token is invalid
        debugPrint('❌ Token validation failed (status ${response.statusCode})');

        // Clear the invalid token
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

  // Join a family
  Future<void> joinFamily(int userId, int familyId) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

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

      final response = await client.get(url, headers: headers);
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

      final response = await client.post(url, headers: headers, body: body);
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
}
