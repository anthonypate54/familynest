import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/service_provider.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/family_management_screen.dart';
import 'screens/invitations_screen.dart';
import 'screens/message_screen.dart';
import 'theme/app_theme.dart';
import 'utils/page_transitions.dart';
import 'config/app_config.dart';
import 'config/env_config.dart'; // Import the EnvConfig class
import 'components/bottom_navigation.dart';
import 'controllers/bottom_navigation_controller.dart';
import 'dart:io' show Platform; // For platform detection
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // For Timer
import 'package:device_info_plus/device_info_plus.dart'; // For device infoimport 'screens/test_thread_screen.dart';
import 'package:provider/provider.dart';
import 'providers/message_provider.dart';

// Function to get device model name
Future<String?> getDeviceModel() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    return androidInfo.model;
  }
  return null;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment configuration
  await EnvConfig.initialize();

  // Initialize app configuration with the URL from the environment
  final config = AppConfig();
  config.setCustomBaseUrl(EnvConfig().apiUrl);

  debugPrint('🌐 Using API URL: ${EnvConfig().apiUrl}');
  debugPrint('🌍 Environment: ${EnvConfig().environment}');
  debugPrint('📱 Platform: ${Platform.operatingSystem}');

  // Set environment based on environment variable
  if (EnvConfig().isProduction) {
    config.setEnvironment(Environment.production);
  } else {
    config.setEnvironment(Environment.development);
  }

  // Initialize ApiService
  final apiService = ApiService();
  try {
    await apiService.initialize();
    debugPrint('✅ ApiService initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing ApiService: $e');
    // Continue anyway, the service will handle errors appropriately
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
      ],
      child: MyApp(initialRoute: '/'),
    ),
  );
}

class MyApp extends StatefulWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late Future<Map<String, dynamic>?> _initializationFuture;
  final ServiceProvider _serviceProvider = ServiceProvider();

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initialize();
  }

  Future<Map<String, dynamic>?> _initialize() async {
    debugPrint('🔄 APP: Starting app initialization');

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Simple check using provider
      if (apiService.isLoggedIn) {
        debugPrint('🔐 APP: User is logged in, getting user data');

        // Just read from SharedPreferences
        final userId = prefs.getString('user_id');
        final userRole = prefs.getString('user_role') ?? 'USER';

        if (userId != null) {
          debugPrint(
            '✅ APP: Found user data - userId: $userId, role: $userRole',
          );
          // Initialize services only after confirming user is logged in
          _serviceProvider.initialize(apiService);
          return {'userId': int.parse(userId), 'role': userRole};
        }
      }

      debugPrint('🔒 APP: Not logged in or no user data found');
      return null;
    } catch (e) {
      debugPrint('❌ APP: Error during initialization: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyNest',
      theme: AppTheme.lightTheme,
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return null;
        }
        if (settings.arguments is Widget) {
          return SlidePageRoute(
            page: settings.arguments as Widget,
            settings: settings,
          );
        }
        return null;
      },
      onUnknownRoute: (settings) {
        return SlidePageRoute(
          page: const Scaffold(body: Center(child: Text('Route not found'))),
          settings: settings,
        );
      },
      home: FutureBuilder<Map<String, dynamic>?>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final user = snapshot.data;
          if (user != null) {
            return MainAppContainer(
              userId: user['userId'],
              userRole: user['role'] ?? 'USER',
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class MainAppContainer extends StatefulWidget {
  final int userId;
  final String userRole;

  const MainAppContainer({
    super.key,
    required this.userId,
    required this.userRole,
  });

  @override
  MainAppContainerState createState() => MainAppContainerState();
}

class MainAppContainerState extends State<MainAppContainer> {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  int _pendingInvitationsCount = 0;
  final BottomNavigationController _navigationController =
      BottomNavigationController();

  // Initialize PageController directly at declaration to avoid LateInitializationError
  final PageController _pageController = PageController();

  // Add a timer instance variable to allow cancellation
  Timer? _authCheckTimer;

  @override
  void initState() {
    super.initState();
    _screens = [
      MessageScreen(userId: widget.userId.toString()),
      ProfileScreen(
        userId: widget.userId,
        userRole: widget.userRole,
        navigationController: _navigationController,
      ),
      FamilyManagementScreen(
        userId: widget.userId,
        navigationController: _navigationController,
      ),
      InvitationsScreen(
        userId: widget.userId,
        navigationController: _navigationController,
      ),
    ];

    // Set initial page after _currentIndex is properly initialized
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }

    // Register callbacks
    _navigationController.updatePendingInvitationsCount = (count) {
      setState(() {
        _pendingInvitationsCount = count;
      });
    };

    _navigationController.refreshUserFamiliesCallback = () {
      debugPrint('Family data refresh requested');
    };

    // Start an immediate check to ensure we're authenticated
    _checkAuthenticationState();
  }

  // Check if we're still authenticated
  Future<void> _checkAuthenticationState() async {
    try {
      // If token is missing or invalid, this will throw an exception
      final apiService = Provider.of<ApiService>(context, listen: false);
      final user = await apiService.getCurrentUser();

      // If we got null but didn't throw an exception, we're not authenticated
      if (user == null && mounted) {
        debugPrint('Authentication check failed - redirecting to login');
        _redirectToLogin();
      }
    } catch (e) {
      if (e.toString().contains('401') ||
          e.toString().contains('403') ||
          e.toString().contains('Not authenticated')) {
        debugPrint('Authentication error detected: $e');
        if (mounted) {
          _redirectToLogin();
        }
      } else {
        // For other errors (like network issues), don't redirect
        debugPrint('Non-authentication error in periodic check: $e');
      }
    }
  }

  // Redirect to login screen
  void _redirectToLogin() {
    // Use a delayed call to avoid build issues
    Future.delayed(Duration.zero, () {
      if (!mounted) return;

      // Use Navigator.pushAndRemoveUntil to completely clear the navigation stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (route) => false, // Remove all previous routes
      );
    });
  }

  @override
  void dispose() {
    // Cancel the timer to prevent memory leaks
    _authCheckTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // THUMBNAIL TEST OVERLAY - add this at the beginning of build
    return Scaffold(
      // Use PageView for native slide animations
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Disable swiping
        children: _screens,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
      // Bottom navigation
      bottomNavigationBar: BottomNavigation(
        currentIndex: _currentIndex,
        userId: widget.userId,
        userRole: widget.userRole,
        controller: _navigationController,
        pendingInvitationsCount: _pendingInvitationsCount,
        onTabChanged: (index) {
          // Animate to the selected page
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
      ),
    );
  }
}
