import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/clean_onboarding_service.dart'; // Use clean service
import '../services/notification_service.dart'; // Add notification service import
import '../services/subscription_api_service.dart'; // Add subscription service
import '../models/user.dart'; // Import User model
import '../models/subscription.dart'; // Import Subscription model
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/gradient_background.dart';
import '../utils/error_codes.dart'; // Add error codes import
import 'subscription_required_screen.dart'; // Import subscription required screen

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _registrationFormKey = GlobalKey<FormState>();

  // Login form controllers
  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Registration form controllers
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _isRegistering = false;
  final String _selectedRole = 'USER';
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword =
      true; // Separate visibility for confirm password

  // Per-field error states
  String? _usernameError;
  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  // Track which fields have been focused
  bool _usernameFocused = false;
  bool _firstNameFocused = false;
  bool _lastNameFocused = false;
  bool _emailFocused = false;
  bool _passwordFocused = false;
  bool _confirmPasswordFocused = false;

  // Focus nodes for focus-loss detection
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // Simple focus-loss validation for each field
    _usernameFocusNode.addListener(() {
      if (_usernameFocusNode.hasFocus) {
        _usernameFocused = true;
      } else if (_usernameFocused && _usernameController.text.isNotEmpty) {
        _validateUsername();
      }
    });

    _firstNameFocusNode.addListener(() {
      if (_firstNameFocusNode.hasFocus) {
        _firstNameFocused = true;
      } else if (_firstNameFocused && _firstNameController.text.isNotEmpty) {
        _validateFirstName();
      }
    });

    _lastNameFocusNode.addListener(() {
      if (_lastNameFocusNode.hasFocus) {
        _lastNameFocused = true;
      } else if (_lastNameFocused && _lastNameController.text.isNotEmpty) {
        _validateLastName();
      }
    });

    _emailFocusNode.addListener(() {
      if (_emailFocusNode.hasFocus) {
        _emailFocused = true;
      } else if (_emailFocused && _regEmailController.text.isNotEmpty) {
        _validateEmail();
      }
    });

    _passwordFocusNode.addListener(() {
      if (_passwordFocusNode.hasFocus) {
        _passwordFocused = true;
      } else if (_passwordFocused && _regPasswordController.text.isNotEmpty) {
        _validatePassword();
      }
    });

    _confirmPasswordFocusNode.addListener(() {
      if (_confirmPasswordFocusNode.hasFocus) {
        _confirmPasswordFocused = true;
      } else if (_confirmPasswordFocused &&
          _confirmPasswordController.text.isNotEmpty) {
        _validateConfirmPassword();
      }
    });

    // Re-validate confirm password when password changes
    _regPasswordController.addListener(() {
      if (_confirmPasswordController.text.isNotEmpty) {
        _validateConfirmPassword();
      }
    });

    // Add a slight delay to let the UI initialize before checking login
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _checkLoggedInUser();
      }
    });
  }

  @override
  void dispose() {
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _confirmPasswordController.dispose();

    // Dispose focus nodes
    _usernameFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();

    super.dispose();
  }

  Future<void> _checkLoggedInUser() async {
    try {
      debugPrint('LOGIN_SCREEN: Starting auto-login check...');

      // Get apiService before any async operations
      final apiService = Provider.of<ApiService>(context, listen: false);

      // First check if explicitly logged out
      final prefs = await SharedPreferences.getInstance();
      final wasExplicitlyLoggedOut =
          prefs.getBool('explicitly_logged_out') ?? false;

      if (wasExplicitlyLoggedOut) {
        debugPrint(
          'LOGIN_SCREEN: Skipping auto-login check due to explicit logout flag',
        );
        return; // Stay on login screen
      }

      final userResponse = await apiService.getCurrentUser();

      if (userResponse != null && mounted) {
        // Extract user data
        final userId = userResponse['userId'];
        final userRole = userResponse['role'] ?? 'USER';

        debugPrint(
          'LOGIN_SCREEN: Auto-login successful, userId: $userId, role: $userRole',
        );

        // Only navigate if we have a valid user ID
        if (userId != null) {
          // Check onboarding state for simple routing
          final user = User.fromJson(userResponse);
          final onboardingState = user.onboardingState;

          debugPrint(
            'LOGIN_SCREEN: Auto-login user $userId has onboarding_state: $onboardingState',
          );

          // Register FCM token with backend after successful auto-login
          try {
            final apiService = Provider.of<ApiService>(context, listen: false);
            await NotificationService.sendTokenToBackend(
              userId.toString(),
              apiService,
            );
            debugPrint(
              'FCM token registered with backend for auto-login user $userId',
            );
          } catch (e) {
            debugPrint('$e');
            // Don't block auto-login flow if FCM token registration fails
          }

          // Use OnboardingService to route based on onboarding state bitmap
          if (mounted) {
            await CleanOnboardingService.routeAfterLogin(
              context,
              userId,
              userRole,
              onboardingState ?? 0,
            );
          }
        } else {
          debugPrint('LOGIN_SCREEN: Not navigating - userId is null');
        }
      } else {
        // No valid login found
        debugPrint(
          'LOGIN_SCREEN: No valid login credentials found, staying at login screen',
        );
      }
    } catch (e) {
      // Handle any errors during auto-login check
      debugPrint('LOGIN_SCREEN: Error during auto-login check: $e');
      // Stay on login screen
    }
  }

  // Individual field validation methods
  void _validateUsername() {
    final value = _usernameController.text;
    String? error;

    if (value.isEmpty) {
      error = 'Please enter a username';
    } else if (value.length < 3) {
      error = 'Username must be at least 3 characters';
    }

    setState(() {
      _usernameError = error;
    });
  }

  void _validateFirstName() {
    final value = _firstNameController.text;
    String? error;

    if (value.isEmpty) {
      error = 'Please enter your first name';
    }

    setState(() {
      _firstNameError = error;
    });
  }

  void _validateLastName() {
    final value = _lastNameController.text;
    String? error;

    if (value.isEmpty) {
      error = 'Please enter your last name';
    }

    setState(() {
      _lastNameError = error;
    });
  }

  void _validateEmail() {
    final value = _regEmailController.text;
    String? error;

    if (value.isEmpty) {
      error = 'Please enter your email';
    } else {
      final emailRegex = RegExp(
        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      );
      if (!emailRegex.hasMatch(value)) {
        error = 'Please enter a valid email address';
      }
    }

    setState(() {
      _emailError = error;
    });
  }

  void _validatePassword() {
    final value = _regPasswordController.text;
    String? error;

    if (value.isEmpty) {
      error = 'Please enter your password';
    } else if (value.length < 6) {
      error = 'Password must be at least 6 characters long';
    }

    setState(() {
      _passwordError = error;
    });
  }

  void _validateConfirmPassword() {
    final value = _confirmPasswordController.text;
    String? error;

    if (value.isEmpty) {
      error = 'Please confirm your password';
    } else if (value != _regPasswordController.text) {
      error = 'Passwords do not match';
    }

    setState(() {
      _confirmPasswordError = error;
    });
  }

  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;

    // Get apiService before any async operations
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final response = await apiService.login(
        _loginUsernameController.text,
        _loginPasswordController.text,
      );

      if (response != null) {
        if (!mounted) return;

        // Clear the explicitly_logged_out flag
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('explicitly_logged_out', false);

        final userId = response['userId'];
        final userRole = response['role'] ?? 'USER';

        debugPrint(
          'Login successful for user $userId, checking onboarding state...',
        );

        // Get current user to check onboarding state
        final userResponse = await apiService.getCurrentUser();

        if (userResponse != null && mounted) {
          final user = User.fromJson(userResponse);
          final onboardingState = user.onboardingState;

          debugPrint('User $userId has onboarding_state: $onboardingState');

          // Register FCM token with backend after successful login
          try {
            await NotificationService.sendTokenToBackend(
              userId.toString(),
              apiService,
            );
            debugPrint('FCM token registered with backend for user $userId');
          } catch (e) {
            debugPrint('$e');
            // Don't block login flow if FCM token registration fails
          }

          // Check subscription status first
          final subscriptionApi = SubscriptionApiService(apiService);
          final subscriptionData =
              await subscriptionApi.getSubscriptionStatus();
          final hasActiveAccess =
              subscriptionData?['has_active_access'] ?? false;

          if (!hasActiveAccess && mounted) {
            // User doesn't have access - show subscription required screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder:
                    (context) => SubscriptionRequiredScreen(
                      username: user.username,
                      subscription:
                          subscriptionData != null
                              ? Subscription.fromJson(subscriptionData)
                              : null,
                    ),
              ),
            );
          } else if (mounted) {
            // User has access - use normal onboarding flow
            await CleanOnboardingService.routeAfterLogin(
              context,
              userId,
              userRole,
              onboardingState ?? 0,
            );
          }
        } else {
          // Fallback to normal flow if we can't get user data
          debugPrint('Could not get user data, falling back to normal flow');

          // Still try to register FCM token even in fallback
          try {
            await NotificationService.sendTokenToBackend(
              userId.toString(),
              apiService,
            );
            debugPrint(
              'FCM token registered with backend for user $userId (fallback)',
            );
          } catch (e) {
            debugPrint('$e');
          }

          if (mounted) {
            CleanOnboardingService.normalFlow(context, userId, userRole);
          }
        }
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid username or password';
        });
      }
    } catch (e) {
      debugPrint('Login error: $e');
      setState(() {
        _errorMessage = 'An error occurred during login. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _register() async {
    // Validate all fields manually
    _validateUsername();
    _validateFirstName();
    _validateLastName();
    _validateEmail();
    _validatePassword();
    _validateConfirmPassword();

    // Check if any field has an error
    if (_usernameError != null ||
        _firstNameError != null ||
        _lastNameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmPasswordError != null) {
      return; // Don't proceed if there are validation errors
    }

    setState(() => _isLoading = true);
    try {
      final result = await Provider.of<ApiService>(
        context,
        listen: false,
      ).registerUser(
        username: _usernameController.text,
        email: _regEmailController.text,
        password: _regPasswordController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        userRole: _selectedRole,
        photoPath: null,
      );
      debugPrint('Registration successful, userId: ${result['userId']}');
      if (!mounted) return;
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Registration Successful'),
              content: const Text('You can now log in with your new account.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      // Copy registration credentials to login form
                      _loginUsernameController.text = _usernameController.text;
                      _loginPasswordController.text =
                          _regPasswordController.text;

                      // Switch to login mode
                      _isRegistering = false;

                      // Clear registration form
                      _regEmailController.clear();
                      _regPasswordController.clear();
                      _usernameController.clear();
                      _firstNameController.clear();
                      _lastNameController.clear();
                      _confirmPasswordController.clear();
                      _errorMessage = null;

                      // Clear all field errors
                      _usernameError = null;
                      _firstNameError = null;
                      _lastNameError = null;
                      _emailError = null;
                      _passwordError = null;
                      _confirmPasswordError = null;

                      // Reset focused flags
                      _usernameFocused = false;
                      _firstNameFocused = false;
                      _lastNameFocused = false;
                      _emailFocused = false;
                      _passwordFocused = false;
                      _confirmPasswordFocused = false;

                      // Reset both form validation states
                      _loginFormKey.currentState?.reset();
                      _registrationFormKey.currentState?.reset();
                    });
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      debugPrint('🔴 REGISTRATION_ERROR: Raw exception: $e');
      debugPrint('🔴 REGISTRATION_ERROR: Exception type: ${e.runtimeType}');
      if (!mounted) return;
      setState(() => _isLoading = false);

      // Use the new clean error code parsing approach
      String errorMessage = ErrorCodeMapper.parseErrorMessage(e);
      debugPrint('🔴 REGISTRATION_ERROR: Final error message: $errorMessage');

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Registration Failed'),
              content: Text(errorMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    }
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Login',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          TextFormField(
            controller: _loginUsernameController,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Username *'),
            onFieldSubmitted: (value) => _login(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your username';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPasswordController,
            decoration: const InputDecoration(labelText: 'Password *'),
            obscureText: true,
            onFieldSubmitted: (value) => _login(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _isLoading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Login',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              _showForgotPasswordDialog();
            },
            child: const Text('Forgot Password?'),
          ),
          TextButton(
            onPressed: () {
              _showForgotUsernameDialog();
            },
            child: const Text('Forgot Username?'),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _registrationFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Register',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          // Username field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _usernameController,
                focusNode: _usernameFocusNode,
                decoration: const InputDecoration(labelText: 'Username *'),
              ),
              if (_usernameError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                  child: Text(
                    _usernameError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // First Name field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _firstNameController,
                focusNode: _firstNameFocusNode,
                decoration: const InputDecoration(labelText: 'First Name *'),
              ),
              if (_firstNameError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                  child: Text(
                    _firstNameError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Last Name field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _lastNameController,
                focusNode: _lastNameFocusNode,
                decoration: const InputDecoration(labelText: 'Last Name *'),
              ),
              if (_lastNameError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                  child: Text(
                    _lastNameError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Email field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _regEmailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email *'),
              ),
              if (_emailError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                  child: Text(
                    _emailError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Password field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _regPasswordController,
                focusNode: _passwordFocusNode,
                decoration: InputDecoration(
                  labelText: 'Password *',
                  suffixIcon: ExcludeFocus(
                    child: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                obscureText: _obscurePassword,
              ),
              if (_passwordError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                  child: Text(
                    _passwordError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Confirm Password field
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocusNode,
                decoration: InputDecoration(
                  labelText: 'Confirm Password *',
                  suffixIcon: ExcludeFocus(
                    child: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                obscureText: _obscureConfirmPassword,
              ),
              if (_confirmPasswordError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                  child: Text(
                    _confirmPasswordError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _isLoading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                onPressed: _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Create Account',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final TextEditingController _forgotEmailController =
        TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Forgot Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email to receive a password reset code.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _forgotEmailController,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email *'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  String email = _forgotEmailController.text.trim();
                  if (email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter your email')),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  await _sendPasswordResetRequest(email);
                },
                child: const Text('Send Reset Code'),
              ),
            ],
          ),
    );
  }

  Future<void> _sendPasswordResetRequest(String email) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.forgotPassword(email);
      if (response != null && mounted) {
        // Show the code entry dialog
        _showResetCodeEntryDialog(email);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('An error occurred. Please try again.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending password reset request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showResetCodeEntryDialog(String email) {
    final TextEditingController _resetCodeController = TextEditingController();
    final TextEditingController _newPasswordController =
        TextEditingController();
    final TextEditingController _confirmPasswordController =
        TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Enter Reset Code'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the reset code sent to your email and your new password.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _resetCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Reset Code *',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password *',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password *',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final resetCode = _resetCodeController.text.trim();
                  final newPassword = _newPasswordController.text;
                  final confirmPassword = _confirmPasswordController.text;

                  if (resetCode.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter the reset code'),
                      ),
                    );
                    return;
                  }

                  if (newPassword.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a new password'),
                      ),
                    );
                    return;
                  }

                  if (newPassword != confirmPassword) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passwords do not match')),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  await _resetPassword(email, resetCode, newPassword);
                },
                child: const Text('Reset Password'),
              ),
            ],
          ),
    );
  }

  Future<void> _resetPassword(
    String email,
    String resetCode,
    String newPassword,
  ) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.resetPassword(
        email,
        resetCode,
        newPassword,
      );

      if (response != null && response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password reset successful. You can now login with your new password.',
            ),
          ),
        );
      } else {
        String errorMessage = 'Failed to reset password. Please try again.';
        if (response != null && response['error'] != null) {
          errorMessage = response['error'];
        }

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage)));
        }
      }
    } catch (e) {
      debugPrint('Error resetting password: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showForgotUsernameDialog() {
    final TextEditingController _forgotEmailController =
        TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Forgot Username'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter your email to receive a username reminder.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _forgotEmailController,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email *'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  String email = _forgotEmailController.text.trim();
                  if (email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter your email')),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  await _sendUsernameReminderRequest(email);
                },
                child: const Text('Send Username'),
              ),
            ],
          ),
    );
  }

  Future<void> _sendUsernameReminderRequest(String email) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.forgotUsername(email);
      if (response != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If an account exists with this email, a username reminder has been sent.',
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('An error occurred. Please try again.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending username reminder request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Show either login or registration form
                      _isRegistering
                          ? _buildRegistrationForm()
                          : _buildLoginForm(),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isRegistering = !_isRegistering;
                            _errorMessage = null;

                            // Clear all controllers
                            _loginUsernameController.clear();
                            _loginPasswordController.clear();
                            _regEmailController.clear();
                            _regPasswordController.clear();
                            _usernameController.clear();
                            _confirmPasswordController.clear();
                            _firstNameController.clear();
                            _lastNameController.clear();

                            // Clear all field errors
                            _usernameError = null;
                            _firstNameError = null;
                            _lastNameError = null;
                            _emailError = null;
                            _passwordError = null;
                            _confirmPasswordError = null;

                            // Reset focused flags
                            _usernameFocused = false;
                            _firstNameFocused = false;
                            _lastNameFocused = false;
                            _emailFocused = false;
                            _passwordFocused = false;
                            _confirmPasswordFocused = false;

                            // Reset both form validation states
                            _loginFormKey.currentState?.reset();
                            _registrationFormKey.currentState?.reset();
                          });
                        },
                        child: Text(
                          _isRegistering
                              ? 'Already have an account? Login'
                              : 'Don\'t have an account? Register',
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF66BB6A) // darkGreenAccent
                                    : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
