import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
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
  }) async {
    await initialize();
    try {
      debugPrint('Attempting to register user: $username');
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users'),
      );
      request.fields['userData'] = jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'role': role,
      });

      if (photoPath != null && !kIsWeb) {
        request.files.add(
          await http.MultipartFile.fromPath('photo', photoPath),
        );
      }

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

  Future<Map<String, dynamic>> getUserById(int id) async {
    final headers = {'Content-Type': 'application/json'};
    debugPrint('Token in getUserById: $_token');
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      debugPrint('Authorization header set: Bearer $_token');
    } else {
      debugPrint('No token available, Authorization header not set');
    }
    final response = await client.get(
      Uri.parse('$baseUrl/api/users/$id'),
      headers: headers,
    );
    debugPrint(
      'Get user response: statusCode=${response.statusCode}, body=${response.body}',
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to get user details: statusCode=${response.statusCode}, body=${response.body}',
      );
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
    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/join-family/$familyId'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to join family: ${response.body}');
    }
  }

  Future<void> postMessage(
    int userId,
    String content, {
    String? mediaPath,
    String? mediaType,
  }) async {
    try {
      debugPrint(
        'Posting message with mediaPath: $mediaPath, mediaType: $mediaType',
      );
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/users/$userId/messages'),
      );

      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }

      if (content.isNotEmpty) {
        request.fields['content'] = content;
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

      debugPrint('Sending message request with fields: ${request.fields}');
      if (request.files.isNotEmpty) {
        debugPrint('Request contains ${request.files.length} files');
        for (var file in request.files) {
          debugPrint(
            'File: ${file.field} - ${file.filename} (${file.length} bytes)',
          );
        }
      }

      final response = await request.send();
      debugPrint('Message post response status: ${response.statusCode}');
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 201) {
        debugPrint('Error posting message: $responseBody');
        throw Exception('Failed to post message: $responseBody');
      } else {
        debugPrint('Message posted successfully: $responseBody');
      }
    } catch (e) {
      debugPrint('Error posting message: $e');
      rethrow;
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

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/users/$userId/update-photo'),
    );
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.headers['Content-Type'] = 'multipart/form-data';

    request.files.add(await http.MultipartFile.fromPath('photo', photoPath));

    var response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to update photo: ${response.reasonPhrase}');
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
      final response = await client.post(
        Uri.parse('$baseUrl/api/users/$userId/invite'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'email': email}),
      );
      debugPrint(
        'Invite response: statusCode=${response.statusCode}, body=${response.body}',
      );
      if (response.statusCode != 200) {
        // Try to parse the error message from the response
        try {
          final errorBody = jsonDecode(response.body);
          if (errorBody is String) {
            throw errorBody;
          } else if (errorBody is Map && errorBody.containsKey('error')) {
            throw errorBody['error'];
          }
        } catch (e) {
          // If we can't parse the response, just use the raw body
          throw response.body;
        }
        throw 'Failed to send invitation: ${response.statusCode}';
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
}
