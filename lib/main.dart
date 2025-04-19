import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';

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

  @override
  void initState() {
    super.initState();
    apiService = ApiService();
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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FutureBuilder<Map<String, dynamic>?>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data;
          if (user != null) {
            return ProfileScreen(
              apiService: apiService, // Reuse the same instance
              userId: user['userId'],
              role: user['role'] ?? 'USER',
            );
          }
          return LoginScreen(apiService: apiService); // Reuse the same instance
        },
      ),
    );
  }
}
