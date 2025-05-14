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
import 'package:http/http.dart' as http; // For HTTP requests

void main() {
  // Initialize app configuration
  final config = AppConfig();

  // For development purposes, you can override the base URL here
  // This would be read from environment variables in a CI/CD pipeline
  if (const bool.fromEnvironment('USE_LOCAL_API')) {
    config.setCustomBaseUrl(
      const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:8080',
      ),
    );
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
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

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
    await apiService.initialize();
    debugPrint('ApiService initialized, checking for current user');
    final user = await apiService.getCurrentUser();
    debugPrint('Current user result: $user');
    return user;
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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final user = snapshot.data;
          if (user != null) {
            return MainAppContainer(
              apiService: apiService, // Reuse the same instance
              userId: user['userId'],
              userRole: user['role'] ?? 'USER',
            );
          }
          return LoginScreen(apiService: apiService); // Reuse the same instance
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
  bool _showThumbnailTest = true; // Set to true to display the test
  String? _testThumbnailUrl;
  String? _testVideoUrl;
  String? _testErrorMessage;
  bool _isTestLoading = false;

  @override
  void initState() {
    super.initState();

    // Run the thumbnail test if enabled
    if (_showThumbnailTest) {
      _testThumbnails();
    }

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
  }

  // THUMBNAIL TEST METHOD
  Future<void> _testThumbnails() async {
    setState(() {
      _isTestLoading = true;
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
                _testThumbnailUrl = fullThumbnailUrl;
                _testVideoUrl = videoUrl;
                _isTestLoading = false;
              });
              print('Found thumbnailUrl: $_testThumbnailUrl');
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
