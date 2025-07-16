import 'package:familynest/providers/comment_provider.dart';
import 'package:familynest/providers/dm_message_provider.dart';
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/service_provider.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/family_management_screen.dart';
import 'screens/invitations_screen.dart';
import 'screens/message_screen.dart';
import 'screens/messages_home_screen.dart';
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
import 'providers/theme_provider.dart';
import 'providers/text_size_provider.dart';
import 'models/message.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/websocket_test_screen.dart';
import 'services/websocket_service.dart';
// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';

// Firebase background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🌙 Background message received: ${message.messageId}');
}

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

  // Initialize Firebase (without requesting permissions yet)
  await Firebase.initializeApp();
  debugPrint('🔥 Firebase initialized');

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service (without requesting permissions)
  await NotificationService.initializeBasic();

  // Initialize dotenv first
  bool envLoaded = false;
  try {
    await dotenv.load(fileName: '.env.development');
    debugPrint('✅ Loaded environment configuration from .env.development');
    debugPrint('📡 API URL from env: ${dotenv.env['API_URL']}');
    envLoaded = true;
  } catch (e) {
    debugPrint('⚠️ Failed to load .env.development: $e');
    // Try loading the default .env file as fallback
    try {
      await dotenv.load();
      debugPrint('✅ Loaded environment configuration from .env');
      debugPrint('📡 API URL from env: ${dotenv.env['API_URL']}');
      envLoaded = true;
    } catch (e) {
      debugPrint('⚠️ Failed to load .env: $e');
      // Continue with default values - dotenv will use fallbacks
    }
  }

  if (!envLoaded) {
    debugPrint('⚠️ No environment file loaded, using default configuration');
  }

  // Initialize app configuration
  final config = AppConfig();
  await config.initialize();

  debugPrint('🌐 API URL: ${config.baseUrl}');
  debugPrint(
    '🌍 Environment: ${config.isDevelopment
        ? "development"
        : config.isProduction
        ? "production"
        : "staging"}',
  );
  debugPrint('📱 Platform: ${Platform.operatingSystem}');

  // Use shorter polling interval in development for faster testing
  if (config.isDevelopment) {
    config.invitationPollingInterval = const Duration(seconds: 30);
    debugPrint(
      '🧪 DEVELOPMENT MODE: Using shorter invitation polling interval (30s)',
    );
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
        ChangeNotifierProvider(create: (_) => DMMessageProvider()),
        ChangeNotifierProvider(create: (_) => CommentProvider()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => TextSizeProvider()),
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

      // Always initialize ServiceProvider
      _serviceProvider.initialize(apiService);
      debugPrint('✅ APP: ServiceProvider initialized');

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
      darkTheme: AppTheme.darkTheme,
      themeMode: Provider.of<ThemeProvider>(context).themeMode,
      builder: (context, child) {
        final textScaleFactor =
            Provider.of<TextSizeProvider>(context).textScaleFactor;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        );
      },
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
  final int? initialTabIndex; // Add optional initial tab parameter

  const MainAppContainer({
    super.key,
    required this.userId,
    required this.userRole,
    this.initialTabIndex, // Optional parameter to set initial tab
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
  // Note: _invitationCheckTimer removed - now using WebSocket for real-time updates

  // WebSocket handler for invitations
  WebSocketMessageHandler? _invitationHandler;
  WebSocketService? _webSocketService;

  // Remove loading state flag since we don't need complex onboarding checking
  bool _isCheckingInitialScreen = true;

  @override
  void initState() {
    super.initState();
    _screens = [
      MessageScreen(userId: widget.userId.toString()),
      MessagesHomeScreen(userId: widget.userId),
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

    // Use initial tab index if provided, otherwise check for existing DMs
    if (widget.initialTabIndex != null) {
      debugPrint(
        '🎯 MAIN: Using provided initial tab index: ${widget.initialTabIndex}',
      );
      setState(() {
        _currentIndex = widget.initialTabIndex!;
        _isCheckingInitialScreen = false;
      });

      // Navigate to the specified tab after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });

      // Start notification check after initial tab is set
      _finishInitialization();
    } else {
      // Fall back to existing logic
      _checkForExistingDMs();
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

    // Initial check for pending invitations (WebSocket will handle real-time updates)
    _checkPendingInvitations();

    // Initialize WebSocket service
    _initializeWebSocket();

    // Check for notification permissions
    debugPrint('🔔 MAIN: Starting notification check');
    _checkNotificationPermissions();
  }

  // Called after initial screen check completes
  void _finishInitialization() {
    debugPrint('🎯 MAIN: Initial screen check complete');
  }

  // Initialize WebSocket service once for the entire app
  Future<void> _initializeWebSocket() async {
    try {
      debugPrint('🔌 MAIN: Initializing WebSocket service');
      _webSocketService = Provider.of<WebSocketService>(context, listen: false);
      await _webSocketService!.initialize();

      // Subscribe to invitation updates for real-time badge count
      _setupInvitationWebSocket(_webSocketService!);

      debugPrint('✅ MAIN: WebSocket service initialized');
    } catch (e) {
      debugPrint('❌ MAIN: Error initializing WebSocket service: $e');
    }
  }

  // Setup WebSocket subscription for invitation updates
  void _setupInvitationWebSocket(WebSocketService webSocketService) {
    try {
      // Create invitation handler
      final invitationHandler = (Map<String, dynamic> data) {
        _handleIncomingInvitation(data);
      };

      // Subscribe to invitation updates
      webSocketService.subscribe(
        '/user/${widget.userId}/invitations',
        invitationHandler,
      );
      debugPrint('🔌 MAIN: Subscribed to /user/${widget.userId}/invitations');
    } catch (e) {
      debugPrint('❌ MAIN: Error setting up invitation WebSocket: $e');
    }
  }

  // Handle incoming invitation WebSocket messages
  void _handleIncomingInvitation(Map<String, dynamic> data) {
    try {
      debugPrint('📨 INVITATION: Received WebSocket message: $data');

      final messageType = data['type'] as String?;

      if (messageType == 'NEW_INVITATION') {
        // New invitation received - refresh count
        debugPrint('📨 INVITATION: New invitation received');
        _refreshInvitationCount();
      } else if (messageType == 'INVITATION_ACCEPTED' ||
          messageType == 'INVITATION_DECLINED') {
        // Invitation response received - refresh count
        debugPrint('📨 INVITATION: Invitation response received: $messageType');
        _refreshInvitationCount();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ INVITATION: Error handling WebSocket message: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Refresh invitation count from WebSocket update
  Future<void> _refreshInvitationCount() async {
    try {
      // Check if widget is still mounted before using context
      if (!mounted) {
        debugPrint('⚠️ INVITATION: Widget unmounted, skipping refresh');
        return;
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      final invitations = await apiService.getInvitations();

      final pendingCount =
          invitations
              .where(
                (inv) => inv['status'] != null && inv['status'] == 'PENDING',
              )
              .length;

      if (mounted) {
        setState(() {
          _pendingInvitationsCount = pendingCount;
        });
        debugPrint('✅ INVITATION: Updated badge count to $pendingCount');
      }
    } catch (e) {
      debugPrint('❌ INVITATION: Error refreshing count: $e');
    }
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

  // Check for pending invitations and update badge count
  Future<void> _checkPendingInvitations() async {
    try {
      debugPrint('🔍 Initial check for pending invitations...');

      // Check if widget is still mounted before using context
      if (!mounted) {
        debugPrint('⚠️ INVITATION: Widget unmounted, skipping initial check');
        return;
      }

      final apiService = Provider.of<ApiService>(context, listen: false);

      // Get all invitations
      final invitations = await apiService.getInvitations();

      // Count only PENDING invitations
      final pendingCount =
          invitations
              .where(
                (inv) => inv['status'] != null && inv['status'] == 'PENDING',
              )
              .length;

      // Update the badge count
      if (mounted) {
        setState(() {
          _pendingInvitationsCount = pendingCount;
        });
        debugPrint('✅ Initial load: Found $pendingCount pending invitations');
      }
    } catch (e) {
      debugPrint('❌ Error checking pending invitations: $e');
      // Don't update the count on error - keep the previous value
    }
  }

  // Check for existing DMs and set initial screen accordingly
  Future<void> _checkForExistingDMs() async {
    try {
      debugPrint('🔍 Checking for existing DMs to determine initial screen...');
      if (!mounted) return;

      final apiService = Provider.of<ApiService>(context, listen: false);
      final conversations = await apiService.getDMConversations();

      if (mounted) {
        setState(() {
          if (conversations.isNotEmpty) {
            debugPrint('🔍 STARTUP: Has DMs - navigating to DM screen');
            _currentIndex = 1; // DM screen index
          } else {
            debugPrint('🔍 STARTUP: No DMs - staying on MessageScreen');
            _currentIndex = 0; // MessageScreen index
          }
          _isCheckingInitialScreen = false;
        });
        // Start notification check after initial screen is determined
        _finishInitialization();
      }
    } catch (e) {
      debugPrint('❌ Error checking for DMs: $e');
      // On error, proceed with default screen (MessageScreen)
      if (mounted) {
        setState(() {
          _currentIndex = 0; // Default to MessageScreen
          _isCheckingInitialScreen = false;
        });
        // Start notification check even on error
        _finishInitialization();
      }
    }
  }

  // Check for notification permissions after user completes onboarding
  Future<void> _checkNotificationPermissions() async {
    try {
      debugPrint('🔔 MAIN: _checkNotificationPermissions() started');

      // Check if we already have notification permissions
      bool hasPermissions =
          await NotificationService.hasNotificationPermission();
      debugPrint('🔔 MAIN: hasPermissions result: $hasPermissions');

      if (!hasPermissions && mounted) {
        debugPrint(
          '🔔 MAIN: No notification permissions, showing contextual prompt',
        );
        _showNotificationPermissionDialog();
      } else {
        debugPrint('✅ MAIN: User already has notification permissions');
      }
    } catch (e) {
      debugPrint('❌ MAIN: Error checking notification permissions: $e');
    }
  }

  // Show contextual dialog explaining notification benefits
  void _showNotificationPermissionDialog() {
    debugPrint(
      '🔔 MAIN: _showNotificationPermissionDialog() called - showing dialog',
    );
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.notifications_outlined, color: Colors.blue),
                SizedBox(width: 8),
                Text('Stay Connected'),
              ],
            ),
            content: const Text(
              'Get notified when family members send messages, photos, or updates '
              'so you never miss important family moments.\n\n'
              'You can change this setting anytime in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  debugPrint('🔔 MAIN: User chose to enable notifications');
                  await NotificationService.requestPermissionsAndEnable();
                },
                child: const Text('Enable Notifications'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    // Cancel the timer to prevent memory leaks
    _authCheckTimer?.cancel();
    // Note: _invitationCheckTimer removed - now using WebSocket instead of polling
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while determining initial screen
    if (_isCheckingInitialScreen) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // Use PageView for native slide animations
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Disable swiping
        children: _screens,
        onPageChanged: (index) {
          final screenNames = [
            'MessageScreen',
            'MessagesHomeScreen',
            'ProfileScreen',
            'FamilyManagementScreen',
            'InvitationsScreen',
          ];
          debugPrint(
            '📱 PAGE_VIEW: Page changed to $index (${screenNames[index]}) for user ${widget.userId}',
          );

          setState(() {
            _currentIndex = index;
          });
        },
      ),
      floatingActionButton:
          false
              ? FloatingActionButton(
                heroTag: 'ws_test_button',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WebSocketTestScreen(),
                    ),
                  );
                },
                child: const Text('WS Test'),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      // Bottom navigation
      bottomNavigationBar: BottomNavigation(
        currentIndex: _currentIndex,
        userId: widget.userId,
        userRole: widget.userRole,
        controller: _navigationController,
        pendingInvitationsCount: _pendingInvitationsCount,
        onTabChanged: (index) {
          final tabNames = [
            'Messages',
            'DMs',
            'Profile',
            'Family',
            'Invitations',
          ];
          debugPrint(
            '🔀 MAIN_NAV: Tab changed to $index (${tabNames[index]}) for user ${widget.userId}',
          );

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
