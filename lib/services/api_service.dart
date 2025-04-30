import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'dart:async';
import 'dart:io' show Platform, File;

class ApiService {
  // Dynamic baseUrl based on platform
  String get baseUrl {
    if (kIsWeb) {
      return "http://localhost:8080"; // Web
    } else if (Platform.isAndroid) {
      return "http://10.0.0.81:8080"; // Android emulator (pointing to host machine)
    } else {
      return "http://localhost:8080"; // iOS and others
    }
  }

  final http.Client client;
  String? _token;

  ApiService({http.Client? client}) : client = client ?? http.Client();

  Future<void> initialize() async {
    await _loadToken();
    try {
      await testConnection();
    } catch (e) {
      debugPrint('''
❌ Connection test failed with error: $e
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
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    debugPrint('Loaded token from storage: $_token');
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    _token = token;
    debugPrint('Saved token to storage: $token');
    // Verify token was saved
    final savedToken = prefs.getString('auth_token');
    debugPrint('Verified saved token: $savedToken');
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _token = null;
    debugPrint('Cleared token from storage');
  }

  Future<Map<String, dynamic>> loginUser(String email, String password) async {
    try {
      debugPrint('Attempting to login with email: $email');
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      debugPrint(
        'Login response: statusCode=${response.statusCode}, body=${response.body}',
      );
      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        final token = responseBody['token'] as String?;
        if (token != null) {
          await _saveToken(token);
        } else {
          debugPrint('No token received in login response');
          throw Exception('No token received from server');
        }
        return {
          'userId': (responseBody['userId'] as num).toInt(),
          'token': token,
          'role': responseBody['role'] as String? ?? 'USER',
        };
      } else {
        throw Exception(
          'Failed to login: statusCode=${response.statusCode}, body=${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Login failed with error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    debugPrint('Checking for current user, token: $_token');
    if (_token == null) {
      debugPrint('No token available, returning null');
      return null;
    }
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };
      debugPrint(
        'Sending request to $baseUrl/api/users/current with headers: $headers',
      );
      final response = await client.get(
        Uri.parse('$baseUrl/api/users/current'),
        headers: headers,
      );
      debugPrint(
        'Get current user response: statusCode=${response.statusCode}, body=${response.body}',
      );
      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'userId': (responseBody['userId'] as num).toInt(),
          'role': responseBody['role'] as String? ?? 'USER',
        };
      } else {
        debugPrint('Invalid token, clearing token');
        await _clearToken();
        return null;
      }
    } catch (e) {
      debugPrint('Error getting current user: $e');
      await _clearToken();
      return null;
    }
  }

  Future<Map<String, dynamic>> registerUser({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String role = 'USER',
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

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users'),
      );

      // Combine basic user data with demographic data
      final userData = {
        'username': username,
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'role': role,
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
    debugPrint('Logging out, clearing token');
    await _clearToken();
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
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/demographics'),
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

  Future<bool> postMessage(
    int userId,
    String content, {
    String? mediaPath,
    String? mediaType,
    int? familyId,
  }) async {
    try {
      debugPrint('Starting postMessage for userId: $userId');
      debugPrint('Content: "$content"');
      debugPrint('Media path: $mediaPath, media type: $mediaType');
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
      debugPrint(
        'Creating MultipartRequest for POST to $baseUrl/api/users/$userId/messages',
      );

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users/$userId/messages'),
      );

      if (_token != null) {
        debugPrint('Adding authorization token to request');
        request.headers['Authorization'] = 'Bearer $_token';
      } else {
        debugPrint('Warning: No token available for message posting');
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

      if (mediaPath != null && mediaType != null && !kIsWeb) {
        debugPrint('Adding media to message: $mediaPath, type: $mediaType');

        // Check if file exists
        final file = File(mediaPath);
        if (!await file.exists()) {
          debugPrint('Error: File does not exist at path: $mediaPath');
          throw Exception('File does not exist at path: $mediaPath');
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
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$userId/messages'),
      headers: headers,
    );
    debugPrint(
      'Get messages response: status=${response.statusCode}, body=${response.body}',
    );
    if (response.statusCode == 200) {
      final messages =
          (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();

      // Enhanced logging for media content
      for (var message in messages) {
        if (message.containsKey('mediaUrl') && message['mediaUrl'] != null) {
          debugPrint(
            'Message with media: ${message['mediaType']} - ${message['mediaUrl']}',
          );
          debugPrint('Full media URL: $baseUrl${message['mediaUrl']}');
        }
      }

      return messages;
    } else {
      throw Exception('Failed to get messages: ${response.body}');
    }
  }

  Future<void> updatePhoto(int userId, String photoPath) async {
    if (kIsWeb) {
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
        String errorMessage =
            'Failed to send invitation: ${response.statusCode}';

        // Handle specific error cases
        // ... existing error handling ...

        throw errorMessage;
      }
    } catch (e) {
      debugPrint('Error sending invitation: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getInvitations() async {
    if (_token == null) {
      throw Exception('No authentication token available');
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
        throw Exception(
          'Failed to fetch invitations: statusCode=${response.statusCode}, body=${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching invitations: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> acceptInvitation(int invitationId) async {
    if (_token == null) {
      throw Exception('No authentication token available');
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
      } else {
        throw Exception(
          'Failed to accept invitation: statusCode=${response.statusCode}, body=${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error accepting invitation: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rejectInvitation(int invitationId) async {
    if (_token == null) {
      throw Exception('No authentication token available');
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
      } else {
        throw Exception(
          'Failed to reject invitation: statusCode=${response.statusCode}, body=${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error rejecting invitation: $e');
      rethrow;
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

  // Helper method to get the current token
  Future<String?> getToken() async {
    if (_token == null) {
      await _loadToken();
    }
    return _token;
  }
}
