import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'family_management_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String? role;

  const ProfileScreen({
    super.key,
    required this.apiService,
    required this.userId,
    required this.role,
  });

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<Map<String, dynamic>?> _loadUser() async {
    try {
      final user = await widget.apiService.getUserById(widget.userId);
      debugPrint('User data loaded: $user');
      return user;
    } catch (e) {
      debugPrint('Error loading user: $e');
      return null;
    }
  }

  Future<void> _updatePhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      File photoFile = File(pickedFile.path);
      try {
        await widget.apiService.updatePhoto(widget.userId, photoFile);
        setState(() {}); // Trigger FutureBuilder to reload user
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo updated successfully!')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating photo: $e')));
      }
    }
  }

  Future<void> _logout() async {
    widget.apiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(apiService: widget.apiService),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.message),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => HomeScreen(
                        apiService: widget.apiService,
                        userId: widget.userId,
                      ),
                ),
              );
            },
            tooltip: 'Go to Messages',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _loadUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            // Redirect to LoginScreen if user data fails to load
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => LoginScreen(apiService: widget.apiService),
                ),
                (route) => false,
              );
            });
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (user['photo'] != null)
                  Builder(
                    builder: (context) {
                      final photoUrl =
                          '${widget.apiService.baseUrl}${user['photo']}';
                      debugPrint(
                        'Attempting to load photo from URL: $photoUrl',
                      );
                      return Image.network(
                        photoUrl,
                        height: 150,
                        width: 150,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('Error loading photo: $error');
                          return const Icon(
                            Icons.error,
                            size: 150,
                            color: Colors.red,
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          debugPrint(
                            'Loading progress: ${loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : 'unknown'}',
                          );
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                      );
                    },
                  )
                else
                  const Icon(Icons.person, size: 150, color: Colors.grey),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _updatePhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Update Photo',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => FamilyManagementScreen(
                              apiService: widget.apiService,
                              userId: widget.userId,
                            ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Manage Family',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Username: ${user['username']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'First Name: ${user['firstName']}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Last Name: ${user['lastName']}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Role: ${widget.role ?? 'Unknown'}',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
