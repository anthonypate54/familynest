import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/service_provider.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';
import 'utils/page_transitions.dart';

void main() {
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
            return ProfileScreen(
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
