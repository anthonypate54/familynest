import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/api_service.dart';
import 'home_screen.dart';
import 'family_management_screen.dart';
import 'login_screen.dart';
import '../components/bottom_navigation.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:math';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../models/invitation.dart';
import '../services/service_provider.dart';
import '../services/invitation_service.dart';
import '../utils/page_transitions.dart';
import '../controllers/bottom_navigation_controller.dart';
import '../utils/auth_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String userRole;
  final BottomNavigationController? navigationController;

  const ProfileScreen({
    super.key,
    required this.apiService,
    required this.userId,
    required this.userRole,
    this.navigationController,
  });

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  XFile? _photoFile;
  Future<Map<String, dynamic>?>? _userDataFuture;
  final _profileKey = GlobalKey<State>();
  late BottomNavigationController _navigationController;

  // Tab controller for Profile/Invitations tabs
  late TabController _tabController;

  // Invitations data
  List<Map<String, dynamic>> _invitations = [];
  bool _isLoadingInvitations = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();

    // Use the provided controller or create a new one
    _navigationController =
        widget.navigationController ?? BottomNavigationController();
    _userDataFuture = _loadUser();
    _loadInvitations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Load invitations using the improved invitation service
  Future<void> _loadInvitations() async {
    // Get the service just when needed
    final invitationService = ServiceProvider().invitationService;

    await invitationService.loadInvitations(
      userId: widget.userId,
      setLoadingState: (isLoading) {
        if (mounted) {
          setState(() {
            _isLoadingInvitations = isLoading;
          });
        }
      },
      setInvitationsState: (invitations) {
        if (mounted) {
          setState(() {
            _invitations = invitations;
          });
        }
      },
      checkIfMounted: () => mounted,
    );
  }

  // Respond to an invitation using the invitation service
  Future<void> _respondToInvitation(int invitationId, bool accept) async {
    try {
      setState(() => _isLoadingInvitations = true);

      // Get the service just when needed
      final invitationService = ServiceProvider().invitationService;

      final success = await invitationService.respondToInvitation(
        invitationId,
        accept,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'Invitation accepted!' : 'Invitation declined',
            ),
          ),
        );
      } else {
        throw Exception('Failed to process invitation');
      }

      // Refresh all data
      await _loadInvitations();
      if (_navigationController != null) {
        _navigationController!.refreshUserFamilies();
      }
    } catch (e) {
      debugPrint('Error responding to invitation: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoadingInvitations = false);
      }
    }
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
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 30, // Compress image to 30% quality
        maxWidth: 500, // Limit width to 500 pixels
        maxHeight: 500, // Limit height to 500 pixels
      );

      if (pickedFile != null) {
        // Show loading indicator
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing image...'),
                  ],
                ),
              ),
        );

        // Handle file size checking
        int fileSizeKB = 0;

        setState(() {
          _photoFile = pickedFile;
        });

        // Attempt upload
        try {
          if (kIsWeb) {
            try {
              // For web browsers, read the bytes and send
              final bytes = await pickedFile.readAsBytes();
              fileSizeKB = bytes.length ~/ 1024;
              debugPrint('Web image size: $fileSizeKB KB');

              if (bytes.length > 800 * 1024) {
                // 800KB limit
                // Close the progress dialog
                if (!mounted) return;
                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Image is too large ($fileSizeKB KB). Please choose a smaller image.',
                    ),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
                return;
              }

              // Upload the file using the web-specific method
              await widget.apiService.updatePhotoWeb(
                widget.userId,
                bytes,
                '${DateTime.now().millisecondsSinceEpoch}.jpg',
              );

              // Refresh user data
              setState(() {
                _userDataFuture = _loadUser();
              });

              // Close the progress dialog
              if (!mounted) return;
              Navigator.of(context).pop();

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Profile photo updated successfully!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            } catch (e) {
              // Close the progress dialog
              if (!mounted) return;
              Navigator.of(context).pop();

              // Show error message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error uploading image: $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          } else {
            // For mobile platforms, proceed with upload
            final file = File(pickedFile.path);
            final int fileSize = await file.length();
            fileSizeKB = fileSize ~/ 1024;
            debugPrint('Selected photo size: $fileSizeKB KB');

            if (fileSize > 800 * 1024) {
              // 800KB
              // Close the progress dialog
              if (!mounted) return;
              Navigator.of(context).pop();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Image is too large ($fileSizeKB KB). Please choose a smaller image.',
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }

            await widget.apiService.updatePhoto(widget.userId, pickedFile.path);

            // Refresh the user data after successful upload
            setState(() {
              _userDataFuture = _loadUser();
            });

            // Close the progress dialog
            if (!mounted) return;
            Navigator.of(context).pop();

            // Show success animation
            showDialog(
              context: context,
              builder:
                  (context) => Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Photo Updated!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your profile photo has been updated successfully.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(200, 45),
                            ),
                            child: const Text('Great!'),
                          ),
                        ],
                      ),
                    ),
                  ),
            );
          }
        } catch (e) {
          // Close the progress dialog
          if (!mounted) return;
          Navigator.of(context).pop();

          // Create a user-friendly error message
          String errorMessage = 'Unable to update profile photo';

          if (e.toString().contains('413')) {
            errorMessage =
                'The server rejected the image. Please try a smaller or more compressed image.';
          } else if (e.toString().contains('network')) {
            errorMessage =
                'Network error. Please check your connection and try again.';
          } else {
            errorMessage = 'Error updating photo: $e';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _logout() async {
    await AuthUtils.showLogoutConfirmation(context, widget.apiService);
  }

  Future<void> _sendInvitation() async {
    try {
      // First check if user has a family
      final userData = await widget.apiService.getUserById(widget.userId);
      final familyId = userData['familyId'];

      if (familyId == null) {
        _showCreateFamilyFirstDialog();
        return;
      }

      // User has a family, proceed with invitation
      final TextEditingController emailController = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Send Invitation'),
            content: TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context); // Close the dialog immediately

                  // Show a loading indicator
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sending invitation...'),
                      duration: Duration(seconds: 1),
                    ),
                  );

                  try {
                    // Use invitation service to send invitation
                    final invitationService =
                        ServiceProvider().invitationService;
                    final success = await invitationService.inviteUserToFamily(
                      widget.userId,
                      emailController.text,
                    );

                    if (!mounted) return;

                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invitation sent successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      throw Exception('Failed to send invitation');
                    }
                  } catch (e) {
                    if (!mounted) return;
                    debugPrint('Error sending invitation: $e');

                    String errorMessage = e.toString();

                    // Check if it's the database error we fixed
                    if (errorMessage.contains('invitee_email') ||
                        errorMessage.contains('constraint') ||
                        errorMessage.contains('null value in column')) {
                      // Show a specific message that's more helpful
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Error sending invitation: ${emailController.text}. Please try a different email.',
                          ),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    } else if (errorMessage.contains(
                      'already in your family',
                    )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'This person is already in your family!',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else if (errorMessage.contains('already pending')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'There is already a pending invitation for this email.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else if (errorMessage.contains('Server error') ||
                        errorMessage.contains('500')) {
                      // Only show the backend error dialog for server errors
                      _showInvitationBackendError();
                    } else {
                      // For other errors, show a snackbar with the message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $errorMessage'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Send'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint('Error checking user family status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Update demographics information
  Future<void> _updateDemographics(Map<String, dynamic> data) async {
    try {
      await widget.apiService.updateDemographics(widget.userId, data);

      // Refresh the user data
      setState(() {
        _userDataFuture = _loadUser();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demographics updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating demographics: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Show dialog to edit demographics
  Future<void> _showDemographicsDialog(Map<String, dynamic> user) async {
    final TextEditingController phoneController = TextEditingController(
      text: user['phoneNumber'] as String? ?? '+1 ',
    );
    final TextEditingController addressController = TextEditingController(
      text: user['address'] as String? ?? '',
    );
    final TextEditingController cityController = TextEditingController(
      text: user['city'] as String? ?? '',
    );
    final TextEditingController stateController = TextEditingController(
      text: user['state'] as String? ?? '',
    );
    final TextEditingController zipController = TextEditingController(
      text: user['zipCode'] as String? ?? '',
    );
    final TextEditingController countryController = TextEditingController(
      text: user['country'] as String? ?? '',
    );
    final TextEditingController birthDateController = TextEditingController(
      text: user['birthDate'] as String? ?? '',
    );
    final TextEditingController bioController = TextEditingController(
      text: user['bio'] as String? ?? '',
    );

    // Phone number formatter
    final phoneFormatter = MaskTextInputFormatter(
      mask: '+# (###) ###-####',
      filter: {"#": RegExp(r'[0-9]')},
      type: MaskAutoCompletionType.lazy,
    );

    // If phone number already exists, try to set the formatter value
    if (phoneController.text.isNotEmpty) {
      try {
        phoneFormatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: phoneController.text),
        );
      } catch (e) {
        // If formatting fails, keep the original text
        debugPrint('Could not format existing phone number: $e');
      }
    }

    // Format for date input and display
    final DateFormat dateFormat = DateFormat('yyyy-MM-dd');

    Future<void> _selectDate(BuildContext context) async {
      // Parse existing date or use current date
      DateTime initialDate;
      try {
        initialDate =
            birthDateController.text.isNotEmpty
                ? dateFormat.parse(birthDateController.text)
                : DateTime.now().subtract(
                  const Duration(days: 365 * 70),
                ); // Default to 70 years ago
      } catch (e) {
        initialDate = DateTime.now().subtract(const Duration(days: 365 * 70));
      }

      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        initialDatePickerMode:
            DatePickerMode.year, // Start with year view for easier navigation
        builder: (BuildContext context, Widget? child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Theme.of(context).colorScheme.primary,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
              dialogBackgroundColor: Colors.white,
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        birthDateController.text = dateFormat.format(picked);
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Center(child: Text('Edit Info')),
          titlePadding: const EdgeInsets.only(top: 20, bottom: 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    icon: Icon(Icons.phone),
                    helperText: 'Format: +1 (123) 456-7890',
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [phoneFormatter],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    icon: Icon(Icons.home),
                    helperText: 'Enter your street address',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    icon: Icon(Icons.location_city),
                    helperText: 'City you currently live in',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: stateController,
                  decoration: const InputDecoration(
                    labelText: 'State/Province',
                    icon: Icon(Icons.map),
                    helperText: 'State or province of residence',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: zipController,
                  decoration: const InputDecoration(
                    labelText: 'Zip/Postal Code',
                    icon: Icon(Icons.pin),
                    helperText: '5-digit postal code',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: countryController,
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    icon: Icon(Icons.public),
                    helperText: 'Country of residence',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: birthDateController,
                  decoration: const InputDecoration(
                    labelText: 'Birth Date',
                    icon: Icon(Icons.cake),
                    suffixIcon: Icon(Icons.calendar_today),
                    helperText: 'Click to select from calendar',
                  ),
                  readOnly: true,
                  onTap: () => _selectDate(context),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bioController,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    icon: Icon(Icons.info),
                    helperText: 'Tell us about yourself in a few sentences',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final Map<String, dynamic> data = {
                  'phoneNumber':
                      phoneController.text.isEmpty
                          ? null
                          : phoneFormatter.getMaskedText(),
                  'address':
                      addressController.text.isEmpty
                          ? null
                          : addressController.text,
                  'city':
                      cityController.text.isEmpty ? null : cityController.text,
                  'state':
                      stateController.text.isEmpty
                          ? null
                          : stateController.text,
                  'zipCode':
                      zipController.text.isEmpty ? null : zipController.text,
                  'country':
                      countryController.text.isEmpty
                          ? null
                          : countryController.text,
                  'birthDate':
                      birthDateController.text.isEmpty
                          ? null
                          : birthDateController.text,
                  'bio': bioController.text.isEmpty ? null : bioController.text,
                };

                _updateDemographics(data);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Show a message about the invitation backend issue
  void _showInvitationBackendError() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Invitation System Unavailable'),
            content: const Text(
              'We\'re sorry, but the invitation system is currently experiencing technical issues.\n\n'
              'Our team has been notified and is working on a fix. In the meantime, you can still use '
              'the app and enjoy your family connections.\n\n'
              'Please try again later or contact support if the issue persists.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // Add a method to handle the case when user doesn't have a family
  void _showCreateFamilyFirstDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create a Family First'),
            content: const Text(
              'You need to create a family before you can invite others. Would you like to create a family now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  slidePush(
                    context,
                    FamilyManagementScreen(
                      apiService: widget.apiService,
                      userId: widget.userId,
                      navigationController: _navigationController,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Create Family'),
              ),
            ],
          ),
    );
  }

  // Extract the app bar without tabs
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Profile'),
      centerTitle: true,
      backgroundColor: Theme.of(context).colorScheme.primary,
      elevation: 0,
      actions: [
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () {
            setState(() {
              _userDataFuture = _loadUser();
            });
          },
          tooltip: 'Refresh',
        ),
        // Logout button
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _logout,
          tooltip: 'Logout',
        ),
      ],
    );
  }

  // Extract the gradient background container into a separate method
  Widget _buildGradientBackground({required Widget child}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
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
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive width for the profile content
    final double maxWidth = 500;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double contentWidth =
        screenWidth > maxWidth + 40 ? maxWidth : screenWidth - 40;
    final bool isSmallScreen = screenWidth < 360;

    // Count pending invitations for the badge
    final pendingInvitationsCount =
        _invitations.where((inv) => inv['status'] == 'PENDING').length;

    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildGradientBackground(
        child: _buildProfileTab(contentWidth, isSmallScreen),
      ),
    );
  }

  // Profile Tab content with improved structure
  Widget _buildProfileTab(double contentWidth, bool isSmallScreen) {
    return SafeArea(
      key: _profileKey,
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _userDataFuture ?? _loadUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            _redirectToLogin();
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data!;
          return _buildProfileContent(user, contentWidth, isSmallScreen);
        },
      ),
    );
  }

  // Helper method to redirect to login
  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      slidePushAndRemoveUntil(
        context,
        LoginScreen(apiService: widget.apiService),
        (route) => false,
      );
    });
  }

  // Extract the profile content to a separate method
  Widget _buildProfileContent(
    Map<String, dynamic> user,
    double contentWidth,
    bool isSmallScreen,
  ) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: isSmallScreen ? 10 : 20),

              // Profile photo - smaller on small screens
              ProfilePhoto(
                photoUrl:
                    user['photo'] != null
                        ? '${widget.apiService.baseUrl}${user['photo']}?t=${DateTime.now().millisecondsSinceEpoch}'
                        : null,
                onTap: _pickPhoto,
                size: isSmallScreen ? 90 : 110,
              ),

              SizedBox(height: isSmallScreen ? 5 : 10),

              // Edit Info Button
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.edit, size: 24),
                    label: Text(
                      'EDIT INFO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _showDemographicsDialog(user),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                  ),
                ),
              ),

              // Profile info card
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                            child: ProfileInfo(
                              username: user['username'] ?? '',
                              firstName: user['firstName'] ?? '',
                              lastName: user['lastName'] ?? '',
                              email: user['email'] ?? 'Not available',
                              role: widget.userRole ?? 'Unknown',
                              isSmallScreen: isSmallScreen,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: isSmallScreen ? 10 : 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfilePhoto extends StatelessWidget {
  final String? photoUrl;
  final VoidCallback onTap;
  final double size;

  const ProfilePhoto({
    super.key,
    this.photoUrl,
    required this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = size < 100;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: size,
          height: size,
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
                      cacheWidth: (size * 2).toInt(),
                      cacheHeight: (size * 2).toInt(),
                      headers: const {'Cache-Control': 'no-cache'},
                      key: ValueKey(photoUrl),
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.person,
                          size: size * 0.5,
                          color: Colors.grey,
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                    )
                    : Icon(Icons.person, size: size * 0.5, color: Colors.grey),
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
            icon: Icon(
              Icons.camera_alt,
              color: Colors.white,
              size: isSmallScreen ? 16 : 20,
            ),
            onPressed: onTap,
            tooltip: 'Update Photo',
            padding: EdgeInsets.all(isSmallScreen ? 4 : 8),
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
  final bool isSmallScreen;

  const ProfileInfo({
    super.key,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.isSmallScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          context,
          Icons.person,
          'Username',
          username,
          isSmallScreen,
        ),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          Icons.person_outline,
          'First Name',
          firstName,
          isSmallScreen,
        ),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          Icons.person_outline,
          'Last Name',
          lastName,
          isSmallScreen,
        ),
        const Divider(height: 24),
        _buildInfoRow(context, Icons.email, 'Email', email, isSmallScreen),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          Icons.verified_user,
          'Role',
          role,
          isSmallScreen,
        ),
      ],
    );
  }

  static Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    bool isSmallScreen,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: isSmallScreen ? 22 : 28,
        ),
        SizedBox(width: isSmallScreen ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              SizedBox(height: isSmallScreen ? 2 : 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
                softWrap: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
