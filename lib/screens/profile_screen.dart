import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/api_service.dart';
import 'home_screen.dart';
import 'family_management_screen.dart';
import 'login_screen.dart';
import 'invitations_screen.dart';
import '../components/bottom_navigation.dart';

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

class ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  XFile? _photoFile;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

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

  Future<void> _pickPhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _photoFile = pickedFile;
      });
      try {
        // Skip photo upload on web for now
        if (!kIsWeb) {
          await widget.apiService.updatePhoto(widget.userId, pickedFile.path);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully!')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

  Future<void> _sendInvitation() async {
    final TextEditingController emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Invitation'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await widget.apiService.inviteUser(
                    widget.userId,
                    emailController.text,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invitation sent successfully!'),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error sending invitation: $e')),
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive width for the profile content
    final double maxWidth = 500;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double contentWidth =
        screenWidth > maxWidth + 40 ? maxWidth : screenWidth - 40;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        actions: [
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigation(
        currentIndex: 1, // Profile tab
        apiService: widget.apiService,
        userId: widget.userId,
        userRole: widget.role,
        onSendInvitation: (_) => _sendInvitation(),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity, // Fill the entire screen height
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _loadUser(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || snapshot.data == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              LoginScreen(apiService: widget.apiService),
                    ),
                    (route) => false,
                  );
                });
                return const Center(child: CircularProgressIndicator());
              }

              final user = snapshot.data!;

              return FadeTransition(
                opacity: _fadeAnimation,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: contentWidth,
                      minHeight:
                          MediaQuery.of(context).size.height -
                          kToolbarHeight -
                          MediaQuery.of(context).padding.top -
                          MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.start, // Start from the top
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),

                        // Profile photo
                        ProfilePhoto(
                          photoUrl:
                              user['photo'] != null
                                  ? '${widget.apiService.baseUrl}${user['photo']}'
                                  : null,
                          onTap: _pickPhoto,
                        ),

                        const SizedBox(height: 20),

                        // Profile info card
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: ProfileInfo(
                                username: user['username'] ?? '',
                                firstName: user['firstName'] ?? '',
                                lastName: user['lastName'] ?? '',
                                email: user['email'] ?? 'Not available',
                                role: widget.role ?? 'Unknown',
                              ),
                            ),
                          ),
                        ),

                        // Manage family button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.family_restroom),
                            label: const Text('Manage Family'),
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
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class ProfilePhoto extends StatelessWidget {
  final String? photoUrl;
  final VoidCallback onTap;

  const ProfilePhoto({super.key, this.photoUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipOval(
            child:
                photoUrl != null
                    ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.grey,
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                    )
                    : const Icon(Icons.person, size: 60, color: Colors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white),
            onPressed: onTap,
            tooltip: 'Update Photo',
          ),
        ),
      ],
    );
  }
}

class ProfileInfo extends StatelessWidget {
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String role;

  const ProfileInfo({
    super.key,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(context, Icons.person, 'Username', username),
        const Divider(height: 24),
        _buildInfoRow(context, Icons.person_outline, 'First Name', firstName),
        const Divider(height: 24),
        _buildInfoRow(context, Icons.person_outline, 'Last Name', lastName),
        const Divider(height: 24),
        _buildInfoRow(context, Icons.email, 'Email', email),
        const Divider(height: 24),
        _buildInfoRow(context, Icons.verified_user, 'Role', role),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
