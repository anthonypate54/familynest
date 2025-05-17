import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/service_provider.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/family_management_screen.dart';
import 'screens/invitations_screen.dart';
import 'screens/video_player_screen.dart';
import 'theme/app_theme.dart';
import 'utils/page_transitions.dart';
import 'config/app_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'components/bottom_navigation.dart';
import 'controllers/bottom_navigation_controller.dart';
import 'utils/custom_tab_view.dart';
import 'dart:convert'; // For JSON parsing
import 'dart:io' show Platform; // For platform detection
import 'package:http/http.dart' as http; // For HTTP requests
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async'; // For Timer

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clear the image cache at startup to ensure fresh thumbnails
  await DefaultCacheManager().emptyCache();
  CachedNetworkImage.evictFromCache('thumbnailCacheKey');
  PaintingBinding.instance.imageCache.clear();

  // Load initial configuration
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String baseUrl = prefs.getString('baseUrl') ?? 'http://localhost:8080';

  // Initialize app configuration
  final config = AppConfig();

  // Set platform-specific URLs
  if (Platform.isAndroid) {
    // For real Android devices, try multiple possible addresses for the server
    print('📱 Android device detected - setting up multiple server fallbacks');

    // Create a list of possible server addresses to try
    final servers = [
      'http://10.0.0.10:8080', // WiFi IP
      'http://10.0.0.81:8080', // Ethernet IP
      'http://192.168.1.1:8080', // Common router address
      'http://host.docker.internal:8080', // Docker host name
      'http://10.0.2.2:8080', // Standard emulator address
    ];

    // Instead of setting just one URL, store all options in shared preferences
    prefs.setStringList('server_fallbacks', servers);

    // Set the first one as the primary baseUrl
    config.setCustomBaseUrl(servers[0]);

    // Print troubleshooting info
    print('🌐 Server fallbacks configured: $servers');
    print('📋 NETWORK TROUBLESHOOTING:');
    print('1. Make sure your backend server is running');
    print('2. Ensure your phone and computer are on the same WiFi network');
    print(
      '3. App will try multiple server addresses until it finds one that works',
    );
  } else {
    config.setCustomBaseUrl(baseUrl);
  }

  // You could also set different environments based on build flags
  // Example: flutter build --dart-define=ENVIRONMENT=production
  const environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );
  if (environment == 'production') {
    config.setEnvironment(Environment.production);
  } else if (environment == 'staging') {
    config.setEnvironment(Environment.staging);
  }

  // Log current configuration if in debug mode
  if (kDebugMode) {
    print('Initializing app with baseUrl: ${config.baseUrl}');
    print('Environment: $environment');
    print('Platform: ${Platform.operatingSystem}');
    print('Is Android: ${Platform.isAndroid}');
  }

  runApp(MyApp(initialRoute: '/'));
}

class MyApp extends StatefulWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late Future<Map<String, dynamic>?> _initializationFuture;
  late ApiService apiService; // Keep a single instance
  final ServiceProvider _serviceProvider = ServiceProvider();

  @override
  void initState() {
    super.initState();
    apiService = ApiService();
    // Initialize the service provider with the API service
    _serviceProvider.initialize(apiService);
    _initializationFuture = _initialize();
  }

  Future<Map<String, dynamic>?> _initialize() async {
    debugPrint('Starting initialization');

    try {
      // Check for saved preferences to see if we have any token data
      final prefs = await SharedPreferences.getInstance();

      // In debug mode, set the explicitly_logged_out flag to true
      // to prevent auto-login on first run
      if (kDebugMode) {
        await prefs.setBool('explicitly_logged_out', true);
        debugPrint(
          'DEBUG MODE: Set explicitly_logged_out flag to prevent auto-login',
        );

        // For a clean slate in debug mode, clear credentials
        await prefs.remove('auth_token');
        await prefs.remove('auth_token_backup');
        await prefs.remove('user_id');
        await prefs.remove('is_logged_in');
        debugPrint('DEBUG MODE: Clearing saved credentials for fresh login');
      }

      // Log contents of SharedPreferences at app start
      debugPrint('📋 MAIN.DART - SHARED PREFERENCES AT APP START:');
      final allKeys = prefs.getKeys();
      debugPrint('  All keys: $allKeys');
      if (allKeys.contains('user_id')) {
        final userId = prefs.getString('user_id');
        debugPrint('  user_id = "$userId"');
      } else {
        debugPrint('  ⚠️ user_id KEY NOT FOUND!');
      }

      // Initialize the API service, including loading tokens
      await apiService.initialize();

      // Check for saved preferences to see if we have any token data
      final hasToken = prefs.containsKey('auth_token');
      final hasBackupToken = prefs.containsKey('auth_token_backup');
      final hasUserId = prefs.containsKey('user_id');
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final tokenSaveTime = prefs.getString('token_save_time');

      debugPrint('SharedPreferences has token: $hasToken');
      debugPrint('SharedPreferences has backup token: $hasBackupToken');
      debugPrint('SharedPreferences has user_id: $hasUserId');
      debugPrint('SharedPreferences isLoggedIn flag: $isLoggedIn');
      if (tokenSaveTime != null) {
        debugPrint('Token was last saved at: $tokenSaveTime');
      }

      // Try auto-login if we have any authentication data
      if (hasToken || hasBackupToken || (hasUserId && isLoggedIn)) {
        // If there's a token or stored user credentials, attempt to get current user
        debugPrint('Found saved credentials, checking for current user');
        try {
          final user = await apiService.getCurrentUser();

          if (user != null) {
            debugPrint('✅ Auto-login successful with saved credentials');
            return user;
          } else {
            debugPrint(
              '⚠️ Saved credentials are invalid, will need to login again',
            );
            return null;
          }
        } catch (e) {
          debugPrint('⚠️ Error validating saved credentials: $e');

          // Try to get more information about the error
          if (e.toString().contains('type \'Null\'')) {
            debugPrint(
              '❌ Null type error detected - likely a problem with user_id parsing',
            );
          } else if (e.toString().contains('SocketException')) {
            debugPrint('❌ Network error - check your internet connection');
          } else if (e.toString().contains('401') ||
              e.toString().contains('403')) {
            debugPrint('❌ Authentication error - token might be expired');
          }

          return null;
        }
      } else {
        debugPrint('No saved credentials, user will need to login');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error during initialization: $e');
      // Continue to login screen on error
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyNest',
      theme: AppTheme.lightTheme,
      // Define custom page transitions for the entire app
      onGenerateRoute: (settings) {
        // Use named routes if you have them
        if (settings.name == '/') {
          return null; // Let Flutter handle the initial route
        }

        // For all other routes, use slide transition
        if (settings.arguments is Widget) {
          return SlidePageRoute(
            page: settings.arguments as Widget,
            settings: settings,
          );
        }
        return null;
      },
      // Use custom page transitions for unnamed routes too
      onUnknownRoute: (settings) {
        return SlidePageRoute(
          page: const Scaffold(body: Center(child: Text('Route not found'))),
          settings: settings,
        );
      },
      home: FutureBuilder<Map<String, dynamic>?>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          // Always show loading indicator while checking credentials
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading your account...'),
                  ],
                ),
              ),
            );
          }

          // When authentication check is complete
          final user = snapshot.data;
          if (user != null) {
            // If authentication succeeded, show the main app
            return MainAppContainer(
              apiService: apiService,
              userId: user['userId'],
              userRole: user['role'] ?? 'USER',
            );
          }

          // Only show login screen if authentication failed
          return LoginScreen(apiService: apiService);
        },
      ),
    );
  }
}

class MainAppContainer extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String userRole;

  const MainAppContainer({
    super.key,
    required this.apiService,
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

  // THUMBNAIL TEST VARIABLES
  bool _showThumbnailTest = false; // Set to true to display the test
  String? _testThumbnailUrl;
  String? _testVideoUrl;
  String? _testErrorMessage;
  bool _isTestLoading = false;

  // Add a timer instance variable to allow cancellation
  Timer? _authCheckTimer;

  @override
  void initState() {
    super.initState();

    // Run the thumbnail test if enabled
    //  if (_showThumbnailTest) {
    //   _testThumbnails();
    //  }

    // Initialize all screens
    _screens = [
      HomeScreen(
        apiService: widget.apiService,
        userId: widget.userId,
        navigationController: _navigationController,
      ),
      ProfileScreen(
        apiService: widget.apiService,
        userId: widget.userId,
        userRole: widget.userRole,
        navigationController: _navigationController,
      ),
      FamilyManagementScreen(
        apiService: widget.apiService,
        userId: widget.userId,
        navigationController: _navigationController,
      ),
      InvitationsScreen(
        apiService: widget.apiService,
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

    // Periodically check if we're still authenticated
    // This will prevent app from remaining in a broken state after logout
    _authCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _checkAuthenticationState();
    });
  }

  // Check if we're still authenticated
  Future<void> _checkAuthenticationState() async {
    try {
      // If token is missing or invalid, this will throw an exception
      final user = await widget.apiService.getCurrentUser();

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
        MaterialPageRoute(
          builder: (context) => LoginScreen(apiService: widget.apiService),
        ),
        (route) => false, // Remove all previous routes
      );
    });
  }

  // THUMBNAIL TEST METHOD
  Future<void> _testThumbnails() async {
    setState(() {
      _isTestLoading = false;
      _testErrorMessage = null;
    });

    try {
      // Get the base URL from ApiService
      final baseUrl = widget.apiService.baseUrl;
      print('Using base URL: $baseUrl');
      String? videoUrl;

      // Try the local video endpoint first (uses actual uploaded files)
      final localVideoResponse = await http.get(
        Uri.parse('$baseUrl/test/local-video'),
        headers: {'Accept': 'application/json'},
      );

      print('Local video test response: ${localVideoResponse.statusCode}');

      if (localVideoResponse.statusCode == 200) {
        // Parse the response JSON
        final data = json.decode(localVideoResponse.body);
        print('Local video test data: $data');

        // Check if we have messages array with thumbnails
        if (data['messages'] != null && data['messages'].isNotEmpty) {
          final messages = data['messages'] as List;
          for (var msg in messages) {
            // Check for thumbnailUrl or thumbnail_url
            final thumbnailUrl = msg['thumbnailUrl'] ?? msg['thumbnail_url'];

            // Also get the video URL if available
            if (msg['mediaUrl'] != null) {
              // For local files, make sure we have the full URL
              String rawUrl = msg['mediaUrl'].toString();
              if (rawUrl.startsWith('/')) {
                videoUrl = baseUrl + rawUrl;
              } else {
                videoUrl = rawUrl;
              }
              print('Found video URL: $videoUrl');
            }

            if (thumbnailUrl != null) {
              // For local thumbnails, make sure we have the full URL
              String fullThumbnailUrl = thumbnailUrl.toString();
              if (fullThumbnailUrl.startsWith('/')) {
                fullThumbnailUrl = baseUrl + fullThumbnailUrl;
              }

              setState(() {
                _testVideoUrl = videoUrl;
                _isTestLoading = false;
              });
              return;
            }
          }
        }
      }

      // If local endpoint failed, try the video-test endpoint with sample videos
      final videoTestResponse = await http.get(
        Uri.parse('$baseUrl/test/videos'),
        headers: {'Accept': 'application/json'},
      );

      print('Video test response: ${videoTestResponse.statusCode}');

      if (videoTestResponse.statusCode == 200) {
        // Parse the response JSON
        final data = json.decode(videoTestResponse.body);
        print('Video test data: $data');

        // Check if we have messages array with thumbnails
        if (data['messages'] != null && data['messages'].isNotEmpty) {
          final messages = data['messages'] as List;
          for (var msg in messages) {
            // Check for thumbnailUrl or thumbnail_url
            final thumbnailUrl = msg['thumbnailUrl'] ?? msg['thumbnail_url'];

            // Also get the video URL if available
            if (msg['mediaUrl'] != null) {
              videoUrl = msg['mediaUrl'].toString();
              print('Found video URL: $videoUrl');
            }

            if (thumbnailUrl != null) {
              setState(() {
                _testThumbnailUrl = thumbnailUrl;
                _testVideoUrl = videoUrl;
                _isTestLoading = false;
              });
              print('Found thumbnailUrl: $_testThumbnailUrl');
              return;
            }
          }
        }

        setState(() {
          _testErrorMessage = 'No thumbnail URL found in test response';
          _isTestLoading = false;
        });
        return;
      }

      // If first endpoint failed, try the simple test endpoint
      final testResponse = await http.get(
        Uri.parse('$baseUrl/test/test'),
        headers: {'Accept': 'application/json'},
      );

      print('Simple test response: ${testResponse.statusCode}');

      if (testResponse.statusCode == 200) {
        final data = json.decode(testResponse.body);
        print('Simple test data: $data');

        // Extract messages array
        if (data['messages'] != null && data['messages'].isNotEmpty) {
          final messages = data['messages'] as List;
          for (var msg in messages) {
            // Check for thumbnailUrl
            if (msg['thumbnailUrl'] != null) {
              // Also get video URL if available
              if (msg['mediaUrl'] != null) {
                videoUrl = msg['mediaUrl'].toString();
              }

              setState(() {
                _testThumbnailUrl = msg['thumbnailUrl'];
                _testVideoUrl = videoUrl;
                _isTestLoading = false;
              });
              print('Found thumbnailUrl: $_testThumbnailUrl');
              return;
            }
          }
        }
      }

      // If all attempts failed
      setState(() {
        _testErrorMessage = 'Could not get thumbnails from any test endpoint';
        _isTestLoading = false;
      });
    } catch (e) {
      print('Error testing thumbnails: $e');
      setState(() {
        _testErrorMessage = 'Error: $e';
        _isTestLoading = false;
      });
    }
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
    if (_showThumbnailTest) {
      // Create an overlay for testing thumbnails
      final testWidget = Positioned(
        top: 100,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🎬 Thumbnail Test',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _showThumbnailTest = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isTestLoading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (_testErrorMessage != null)
                  Text(
                    'Error: $_testErrorMessage',
                    style: const TextStyle(color: Colors.red),
                  )
                else if (_testThumbnailUrl != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thumbnail URL: $_testThumbnailUrl',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      if (_testVideoUrl != null)
                        Text(
                          'Video URL: $_testVideoUrl',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Image.network(
                            _testThumbnailUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Error loading image: $error',
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress
                                                  .cumulativeBytesLoaded /
                                              loadingProgress
                                                  .expectedTotalBytes!
                                          : null,
                                  color: Colors.white,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_testVideoUrl != null)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => VideoPlayerScreen(
                                      videoUrl: _testVideoUrl!,
                                      isLocalFile: false,
                                    ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Play Video with Chewie'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  )
                else
                  const Text(
                    'No thumbnail URL received',
                    style: TextStyle(color: Colors.orange),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isTestLoading ? null : _testThumbnails,
                  child: const Text('Test Again'),
                ),
              ],
            ),
          ),
        ),
      );

      // Return a stack with the normal UI and the test overlay
      return Scaffold(
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: _screens,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
            testWidget,
          ],
        ),
        bottomNavigationBar: BottomNavigation(
          currentIndex: _currentIndex,
          apiService: widget.apiService,
          userId: widget.userId,
          userRole: widget.userRole,
          controller: _navigationController,
          pendingInvitationsCount: _pendingInvitationsCount,
          onTabChanged: (index) {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
        ),
      );
    }

    // Normal UI without the test overlay
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
        apiService: widget.apiService,
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
