import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/page_transitions.dart';
import '../main.dart'; // Import to access MainAppContainer
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../widgets/gradient_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  bool _isLoading = false;
  bool _isRegistering = false;
  final String _selectedRole = 'USER';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Add a slight delay to let the UI initialize before checking login
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        _checkLoggedInUser();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _checkLoggedInUser() async {
    try {
      debugPrint('LOGIN_SCREEN: Starting auto-login check...');

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

      final user =
          await Provider.of<ApiService>(
            context,
            listen: false,
          ).getCurrentUser();

      if (user != null && mounted) {
        // Extra validation - make sure we have a valid user ID
        final userId = user['userId'];
        final userRole = user['role'] ?? 'USER';

        debugPrint(
          'LOGIN_SCREEN: Auto-login successful, userId: $userId, role: $userRole',
        );

        // Only navigate if we have a valid user ID
        if (userId != null) {
          debugPrint('LOGIN_SCREEN: Navigating to MainAppContainer');
          if (!mounted) return;
          slidePushReplacement(
            context,
            MainAppContainer(userId: userId, userRole: userRole),
          );
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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final response = await Provider.of<ApiService>(
        context,
        listen: false,
      ).login(_emailController.text, _passwordController.text);

      if (response != null) {
        if (!mounted) return;

        // Clear the explicitly_logged_out flag
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('explicitly_logged_out', false);

        debugPrint('Login successful, navigating to main app');
        if (!mounted) return;
        slidePushReplacement(
          context,
          MainAppContainer(
            userId: response['userId'],
            userRole: response['role'] ?? 'USER',
          ),
        );
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid email or password';
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
    setState(() => _isLoading = true);
    try {
      final result = await Provider.of<ApiService>(
        context,
        listen: false,
      ).registerUser(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
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
                      _isRegistering = false;
                      _usernameController.clear();
                      _firstNameController.clear();
                      _lastNameController.clear();
                    });
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      debugPrint('Error registering: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Registration Failed'),
              content: Text('Error registering: $e'),
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isRegistering ? 'Register' : 'Login',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
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
                        if (_isRegistering)
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                            ),

                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a username';
                              }
                              if (value.length < 3) {
                                return 'Username must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                        if (_isRegistering) const SizedBox(height: 16),
                        if (_isRegistering)
                          TextFormField(
                            controller: _firstNameController,
                            decoration: const InputDecoration(
                              labelText: 'First Name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your first name';
                              }
                              return null;
                            },
                          ),
                        if (_isRegistering) const SizedBox(height: 16),
                        if (_isRegistering)
                          TextFormField(
                            controller: _lastNameController,
                            decoration: const InputDecoration(
                              labelText: 'Last Name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your last name';
                              }
                              return null;
                            },
                          ),
                        if (_isRegistering) const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!RegExp(
                              r'^[^@]+@[^@]+\.[^@]+',
                            ).hasMatch(value)) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (_isRegistering && value.length < 6) {
                              return 'Password must be at least 6 characters long';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _isLoading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                              onPressed: _isRegistering ? _register : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                _isRegistering ? 'Create Account' : 'Login',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegistering = !_isRegistering;
                              _errorMessage = null;
                              _emailController.clear();
                              _passwordController.clear();
                              _usernameController.clear();
                              if (!_isRegistering) {
                                _firstNameController.clear();
                                _lastNameController.clear();
                              }
                            });
                          },
                          child: Text(
                            _isRegistering
                                ? 'Already have an account? Login'
                                : 'Don\'t have an account? Register',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
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
      ),
    );
  }
}
