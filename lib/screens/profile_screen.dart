import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/subscription_api_service.dart';
import 'family_management_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'package:intl/intl.dart';

import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../services/service_provider.dart';
import '../utils/page_transitions.dart';
import '../controllers/bottom_navigation_controller.dart';
import '../utils/auth_utils.dart';
import 'package:provider/provider.dart';
import '../widgets/gradient_background.dart';
import '../models/user.dart';
import '../widgets/user_profile_card.dart';
import 'subscription_tab.dart';
import '../models/subscription.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String userRole;
  final BottomNavigationController? navigationController;
  final int? initialTabIndex; // Add parameter to set initial tab

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.navigationController,
    this.initialTabIndex, // Optional parameter for initial tab
  });

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  late AnimationController _animationController;
  Animation<double>? _animation;
  Future<User?>? _userDataFuture;

  // Tab controller for Profile/Subscription tabs
  late TabController _tabController;

  Timer? _saveTimer;
  String? _pendingSaveField;
  String? _pendingSaveValue;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '🔧 PROFILE: Initializing with tab index: ${widget.initialTabIndex}',
    );
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex:
          widget.initialTabIndex ??
          0, // Use provided initial tab or default to 0
    );

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    // Use the provided controller or create a new one
    // widget.navigationController ?? BottomNavigationController(); // Unused
    _userDataFuture = _loadUser();
  }

  @override
  void deactivate() {
    // Save any pending changes immediately when navigating away
    _forceSavePendingChanges();
    super.deactivate();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Force save any pending changes immediately (for navigation away scenarios)
  void _forceSavePendingChanges() {
    if (_saveTimer?.isActive == true &&
        _pendingSaveField != null &&
        _pendingSaveValue != null) {
      _saveTimer?.cancel();
      debugPrint(
        'FORCE SAVING pending changes due to navigation: $_pendingSaveField = "$_pendingSaveValue"',
      );

      // Execute the save immediately (fire and forget)
      _executeSave(_pendingSaveField!, _pendingSaveValue!);

      // Clear pending data
      _pendingSaveField = null;
      _pendingSaveValue = null;
    }
  }

  Future<User?> _loadUser() async {
    try {
      final userMap = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getUserById(widget.userId);
      debugPrint('User data loaded: $userMap');

      final user = User.fromJson(userMap);

      // Fetch real subscription data from backend
      final apiService = Provider.of<ApiService>(context, listen: false);
      debugPrint('🔧 PROFILE: Creating SubscriptionApiService...');
      final subscriptionApi = SubscriptionApiService(apiService);
      debugPrint('🔧 PROFILE: Calling getSubscriptionStatus...');
      final subscriptionData = await subscriptionApi.getSubscriptionStatus();
      debugPrint('🔧 PROFILE: Subscription data result: $subscriptionData');

      Subscription? subscription;
      if (subscriptionData != null) {
        subscription = Subscription.fromJson(subscriptionData);
        debugPrint('✅ Loaded subscription from backend:');
        debugPrint('   Status: ${subscription.statusDisplayText}');
        debugPrint('   Is Trial: ${subscription.isInTrial}');
        debugPrint('   Price: \$${subscription.monthlyPrice}');
        debugPrint('   Platform: ${subscription.platform}');
        debugPrint('   Raw data: $subscriptionData');
      } else {
        // Fallback to mock trial if backend fails
        subscription = Subscription.createTrial(user.id);
        debugPrint('⚠️ Using mock subscription data');
      }

      return user.copyWith(subscription: subscription);
    } catch (e) {
      debugPrint('Error loading user: $e');
      return null;
    }
  }

  Future<void> _pickPhoto() async {
    // Get apiService before any async operations
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 30,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (pickedFile != null && mounted) {
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
                    Text('Updating profile photo...'),
                  ],
                ),
              ),
        );

        try {
          await apiService.updatePhoto(widget.userId, pickedFile.path);

          if (mounted) {
            Navigator.of(context).pop();
            setState(() {
              _userDataFuture = _loadUser();
            });
          }
        } catch (e) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error updating photo: $e')));
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error selecting photo: $e')));
      }
    }
  }

  Future<void> _logout() async {
    await AuthUtils.showLogoutConfirmation(
      context,
      Provider.of<ApiService>(context, listen: false),
    );
  }

  // ignore: unused_element
  Future<void> _sendInvitation() async {
    // Get apiService before any async operations
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      // First check if user has a family
      final userData = await apiService.getUserById(widget.userId);
      final familyId = userData['familyId'];

      if (familyId == null) {
        _showCreateFamilyFirstDialog();
        return;
      }

      // User has a family, proceed with invitation
      final TextEditingController emailController = TextEditingController();
      if (!mounted) return;
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
                  final email = emailController.text.trim();
                  if (email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter an email address'),
                      ),
                    );
                    return;
                  }

                  // Validate email format
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                  if (!emailRegex.hasMatch(email)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid email address'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

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
                    final result = await invitationService.inviteUserToFamily(
                      widget.userId,
                      email,
                    );

                    if (!mounted) return;

                    if (result['success'] == true) {
                      // Success - show enhanced feedback
                      final userExists = result['userExists'] ?? false;
                      final message =
                          result['message'] ?? 'Invitation sent successfully';
                      final recipientName = result['recipientName'];

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }

                      // Show additional info if user exists
                      if (userExists && recipientName != null) {
                        _showUserExistsDialog(email, recipientName);
                      } else if (!userExists) {
                        _showUnregisteredUserDialog(
                          email,
                          result['suggestedEmails'],
                        );
                      }
                    } else {
                      // Handle error with potential suggestions
                      final error =
                          result['error'] ?? 'Failed to send invitation';
                      final suggestedEmails = result['suggestedEmails'];

                      // Handle specific error cases with better UI
                      if (error.contains('already a member of this family')) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } else if (error.contains('already pending')) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'There is already a pending invitation for this email.',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } else if (suggestedEmails != null &&
                          suggestedEmails.isNotEmpty) {
                        _showEmailSuggestionsDialog(
                          email,
                          error,
                          suggestedEmails,
                        );
                      } else {
                        _showErrorSnackBar(error);
                      }
                    }
                  } catch (e) {
                    debugPrint('Error sending invitation: $e');
                    if (!mounted) return;
                    _showErrorSnackBar(
                      'Failed to send invitation: ${e.toString()}',
                    );
                  }
                },
                child: const Text('Send'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint('Error in _sendInvitation: $e');
      if (!mounted) return;
      _showErrorSnackBar('Error: ${e.toString()}');
    }
  }

  // Show dialog when user exists
  void _showUserExistsDialog(String email, String recipientName) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('User Found'),
            content: Text(
              'Invitation sent to $recipientName ($email).\n\nThey will receive a real-time notification if they\'re currently online.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // Show dialog when user doesn't exist
  void _showUnregisteredUserDialog(
    String email,
    List<String>? suggestedEmails,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('📧 Invitation Sent'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invitation sent to $email'),
                const SizedBox(height: 8),
                const Text(
                  'This email address isn\'t registered yet. The person can accept your invitation when they sign up for FamilyNest.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                if (suggestedEmails != null && suggestedEmails.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Did you mean one of these registered users?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...suggestedEmails.map(
                    (suggestedEmail) => TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Trigger another invitation with the suggested email
                        _sendInvitationWithEmail(suggestedEmail);
                      },
                      child: Text(suggestedEmail),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // Show dialog with email suggestions
  void _showEmailSuggestionsDialog(
    String originalEmail,
    String error,
    List<String> suggestedEmails,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Email Not Found'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error),
                const SizedBox(height: 16),
                const Text(
                  'Did you mean one of these registered emails?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...suggestedEmails.map(
                  (suggestedEmail) => ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(suggestedEmail),
                    onTap: () {
                      Navigator.of(context).pop();
                      _sendInvitationWithEmail(suggestedEmail);
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _sendInvitationWithEmail(originalEmail);
                },
                child: const Text('Keep Original'),
              ),
            ],
          ),
    );
  }

  // Helper method to send invitation with a specific email
  Future<void> _sendInvitationWithEmail(String email) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sending invitation...'),
          duration: Duration(seconds: 1),
        ),
      );

      final invitationService = ServiceProvider().invitationService;
      final result = await invitationService.inviteUserToFamily(
        widget.userId,
        email,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final message = result['message'] ?? 'Invitation sent successfully';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
      } else {
        _showErrorSnackBar(result['error'] ?? 'Failed to send invitation');
      }
    } catch (e) {
      debugPrint('Error sending invitation: $e');
      if (!mounted) return;

      String errorMessage;
      if (e is InvitationException) {
        errorMessage = e.message;
      } else {
        errorMessage = e.toString();
      }
      _showErrorSnackBar('Failed to send invitation: $errorMessage');
    }
  }

  // Show error snackbar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // Update demographics information
  Future<void> _updateDemographics(Map<String, dynamic> data) async {
    try {
      await Provider.of<ApiService>(
        context,
        listen: false,
      ).updateDemographics(widget.userId, data);

      // Refresh the user data
      if (mounted) {
        setState(() {
          _userDataFuture = _loadUser();
        });
      }

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

  String _formatBirthDateFromMap(dynamic birthDate) {
    if (birthDate == null) return '';

    try {
      // If it's already a string, return it as is
      if (birthDate is String) {
        return birthDate;
      }

      // If it's an integer timestamp, convert it to a date string
      if (birthDate is int) {
        final date = DateTime.fromMillisecondsSinceEpoch(birthDate);
        return DateFormat('yyyy-MM-dd').format(date);
      }

      // If it's a double, convert to int first
      if (birthDate is double) {
        final date = DateTime.fromMillisecondsSinceEpoch(birthDate.toInt());
        return DateFormat('yyyy-MM-dd').format(date);
      }

      return '';
    } catch (e) {
      debugPrint('Error formatting birth date: $e');
      return '';
    }
  }

  // Show dialog to edit demographics
  // ignore: unused_element
  Future<void> _showDemographicsDialog(Map<String, dynamic> user) async {
    final TextEditingController firstNameController = TextEditingController(
      text: user['firstName'] as String? ?? '',
    );
    final TextEditingController lastNameController = TextEditingController(
      text: user['lastName'] as String? ?? '',
    );
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
      text: _formatBirthDateFromMap(user['birthDate']),
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

    // ignore: unused_element
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
                // Personal Details
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          icon: Icon(Icons.person),
                          helperText: 'Enter your first name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                          icon: Icon(Icons.person_outline),
                          helperText: 'Enter your last name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildEditField(
                  label: 'Phone Number',
                  value: user['phoneNumber'] ?? '',
                  icon: Icons.phone,
                  hint: '+1 (123) 456-7890',
                  onChanged: (value) => _saveField('phoneNumber', value),
                  isPhoneField: true,
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
                  'firstName':
                      firstNameController.text.isEmpty
                          ? null
                          : firstNameController.text,
                  'lastName':
                      lastNameController.text.isEmpty
                          ? null
                          : lastNameController.text,
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
  // ignore: unused_element
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
                    FamilyManagementScreen(userId: widget.userId),
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
  // ignore: unused_element
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
            if (mounted) {
              setState(() {
                _userDataFuture = _loadUser();
              });
            }
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

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading:
              false, // Never show back button - this is a top-level tab
          title: const Text('Profile'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => SettingsScreen(
                          apiService: Provider.of<ApiService>(
                            context,
                            listen: false,
                          ),
                          userId: widget.userId,
                          userRole: widget.userRole,
                        ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await AuthUtils.showLogoutConfirmation(
                  context,
                  Provider.of<ApiService>(context, listen: false),
                );
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            tabs: const [
              Tab(icon: Icon(Icons.person), text: 'Profile'),
              Tab(icon: Icon(Icons.star), text: 'Subscription'),
              Tab(icon: Icon(Icons.edit), text: 'Edit Info'),
            ],
          ),
        ),
        body: FutureBuilder<User?>(
          future: _userDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || snapshot.data == null) {
              return const Center(child: Text('Error loading profile'));
            }

            final user = snapshot.data!;
            final content = TabBarView(
              controller: _tabController,
              children: [
                _buildModernProfileTab(user),
                _buildSubscriptionTab(user),
                _buildEditInfoTab(user),
              ],
            );

            // Only apply animation if it's been initialized
            if (_animation != null &&
                (_animationController.isCompleted ||
                    _animationController.isAnimating)) {
              return FadeTransition(opacity: _animation!, child: content);
            } else {
              return content;
            }
          },
        ),
      ),
    );
  }

  Widget _buildModernProfileTab(User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          UserProfileCard(
            user: user,
            photoUrl:
                user.photo != null
                    ? (user.photo!.startsWith('http')
                        ? user.photo!
                        : '${Provider.of<ApiService>(context, listen: false).mediaBaseUrl}${user.photo}')
                    : null,
            onEditPhoto: _pickPhoto,
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTab(User user) {
    return SubscriptionTab(
      user: user,
      onUserDataRefresh: () {
        setState(() {
          _userDataFuture = _loadUser();
        });
      },
    );
  }

  // Helper method to redirect to login
  // ignore: unused_element
  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      slidePushAndRemoveUntil(context, const LoginScreen(), (route) => false);
    });
  }

  Widget _buildEditInfoTab(User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Personal Details Section
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildEditField(
                          label: 'First Name',
                          value: user.firstName,
                          icon: Icons.person,
                          hint: 'Enter your first name',
                          onChanged: (value) => _saveField('firstName', value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildEditField(
                          label: 'Last Name',
                          value: user.lastName,
                          icon: Icons.person_outline,
                          hint: 'Enter your last name',
                          onChanged: (value) => _saveField('lastName', value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Contact Information Section
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildEditField(
                    label: 'Phone Number',
                    value: user.phoneNumber ?? '',
                    icon: Icons.phone,
                    hint: '+1 (123) 456-7890',
                    onChanged: (value) => _saveField('phoneNumber', value),
                    isPhoneField: true,
                  ),
                  const SizedBox(height: 8),
                  _buildEditField(
                    label: 'Email',
                    value: user.email,
                    icon: Icons.email,
                    hint: 'your.email@example.com',
                    readOnly: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Address',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildEditField(
                    label: 'Street Address',
                    value: user.address ?? '',
                    icon: Icons.home,
                    hint: '123 Main St',
                    onChanged: (value) => _saveField('address', value),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildEditField(
                          label: 'City',
                          value: user.city ?? '',
                          icon: Icons.location_city,
                          hint: 'City',
                          onChanged: (value) => _saveField('city', value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: _buildEditField(
                          label: 'State',
                          value: user.state ?? '',
                          icon: Icons.map,
                          hint: 'OR',
                          onChanged: (value) => _saveField('state', value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildEditField(
                          label: 'Zip Code',
                          value: user.zipCode ?? '',
                          icon: Icons.pin,
                          hint: '97140',
                          onChanged: (value) => _saveField('zipCode', value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildEditField(
                          label: 'Country',
                          value: user.country ?? '',
                          icon: Icons.public,
                          hint: 'USA',
                          onChanged: (value) => _saveField('country', value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildEditField(
                    label: 'Birth Date',
                    value: user.formattedBirthDate,
                    icon: Icons.cake,
                    hint: 'MM/dd/yyyy',
                    onChanged: (value) => _saveField('birthDate', value),
                    isDateField: true,
                  ),
                  const SizedBox(height: 8),
                  _buildEditField(
                    label: 'Bio',
                    value: user.bio ?? '',
                    icon: Icons.info,
                    hint: 'Tell us about yourself...',
                    maxLines: 3,
                    onChanged: (value) => _saveField('bio', value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEditField({
    required String label,
    required String value,
    required IconData icon,
    required String hint,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
    Function(String)? onChanged,
    bool isPhoneField = false,
    bool isDateField = false,
  }) {
    final controller = TextEditingController(text: value);
    final focusNode = FocusNode();

    // Add focus listener for phone formatting
    if (isPhoneField) {
      focusNode.addListener(() {
        if (!focusNode.hasFocus) {
          _formatPhoneNumber(controller, onChanged);
        }
      });
    }

    // Input formatters for different field types
    List<TextInputFormatter> inputFormatters = [];
    if (isDateField) {
      inputFormatters.add(
        MaskTextInputFormatter(
          mask: '##/##/####',
          filter: {"#": RegExp(r'[0-9]')},
          type: MaskAutoCompletionType.lazy,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          readOnly: readOnly,
          onTap: onTap,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          keyboardType:
              isPhoneField
                  ? TextInputType.phone
                  : isDateField
                  ? TextInputType.number
                  : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.green),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          style: const TextStyle(fontSize: 14),
          onChanged:
              isPhoneField
                  ? null
                  : onChanged, // Don't trigger auto-save while typing for phone
        ),
      ],
    );
  }

  void _formatPhoneNumber(
    TextEditingController controller,
    Function(String)? onChanged,
  ) {
    final text = controller.text.replaceAll(
      RegExp(r'[^\d]'),
      '',
    ); // Remove non-digits

    if (text.length == 10) {
      // Format as (123) 456-7890
      final formatted =
          '(${text.substring(0, 3)}) ${text.substring(3, 6)}-${text.substring(6)}';
      controller.text = formatted;

      // Trigger auto-save with formatted number
      onChanged?.call(formatted);
    } else if (text.length == 11 && text.startsWith('1')) {
      // Handle 11-digit numbers starting with 1 (US country code)
      final phoneDigits = text.substring(1); // Remove the leading 1
      final formatted =
          '(${phoneDigits.substring(0, 3)}) ${phoneDigits.substring(3, 6)}-${phoneDigits.substring(6)}';
      controller.text = formatted;

      // Trigger auto-save with formatted number
      onChanged?.call(formatted);
    } else if (text.isNotEmpty && text.length < 10) {
      // For incomplete numbers, just trigger save without formatting
      onChanged?.call(controller.text);
    }
  }

  void _saveField(String field, String value) {
    // Cancel any existing timer
    _saveTimer?.cancel();

    // Store pending save data for force save scenarios
    _pendingSaveField = field;
    _pendingSaveValue = value;

    // Start a new timer to save after 2 seconds of inactivity
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      await _executeSave(field, value);
      // Clear pending data after successful timer execution
      _pendingSaveField = null;
      _pendingSaveValue = null;
    });
  }

  // Execute the save operation (used by both timer and force save)
  Future<void> _executeSave(String field, String value) async {
    try {
      // Create the update data map
      final updateData = {field: value};
      debugPrint(
        'SAVING FIELD: $field = "$value" for userId: ${widget.userId}',
      );
      debugPrint('Update data: $updateData');

      // Call the API to save the field silently
      final response = await Provider.of<ApiService>(
        context,
        listen: false,
      ).updateDemographics(widget.userId, updateData);
      debugPrint('SAVE RESPONSE: $response');

      // No UI feedback - completely seamless
    } catch (e) {
      debugPrint('$e');
      // Only show error messages, no success messages
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving: ${e.toString().contains('Exception:') ? e.toString().split('Exception: ')[1] : e.toString()}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
                color: Colors.black.withValues(alpha: 0.2),
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
                color: Colors.black.withValues(alpha: 0.2),
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
