import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class ApiService {
  // Use different base URLs based on the platform
  final String baseUrl =
      Platform.isAndroid
          ? "http://10.0.0.81:8080" // Android emulator
          : "http://localhost:8080"; // iOS simulator or physical device

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
   - Android Emulator: 10.0.2.2
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
      if (e is SocketException) {
        debugPrint('''
Network connection error. Please check:
1. Is the backend server running? ($baseUrl/api/users/test)
2. Are you using the correct IP address?
   - Android Emulator: 10.0.2.2
   - iOS Simulator: localhost
   - Physical Device: Your computer's local IP
3. Is your device/emulator connected to the same network?
4. Are there any firewall settings blocking the connection?
''');
      }
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
    File? photo,
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
      if (photo != null) {
        request.files.add(
          await http.MultipartFile.fromPath('photo', photo.path),
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

  void logout() {
    debugPrint('Logging out, clearing token');
    _clearToken();
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
      body: jsonEncode({'name': familyName}),
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

  Future<void> postMessage(int userId, String content) async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      debugPrint('Posting message with token: $_token');
    } else {
      debugPrint('No token available for posting message');
    }
    debugPrint('Posting message for user $userId with content: $content');
    final response = await client.post(
      Uri.parse('$baseUrl/api/users/$userId/messages'),
      headers: headers,
      body: jsonEncode({'content': content}),
    );
    debugPrint(
      'Message post response: status=${response.statusCode}, body=${response.body}',
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to post message: ${response.body}');
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
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to get messages: ${response.body}');
    }
  }

  Future<void> updatePhoto(int userId, File photoFile) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/users/$userId/update-photo'),
    );
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.headers['Content-Type'] = 'multipart/form-data';
    request.files.add(
      await http.MultipartFile.fromPath('photo', photoFile.path),
    );
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
}
